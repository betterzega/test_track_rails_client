require 'rails_helper'

RSpec.describe TestTrack::VaryDSL do
  subject do
    described_class.new(
      assignment: assignment,
      split_registry: split_registry,
      context: "the_context"
    )
  end
  let(:assignment) do
    instance_double(TestTrack::Assignment, split_name: "button_size", variant: "one")
  end
  let(:split_registry) do
    {
      'button_size' => {
        'one' => 100,
        'two' => 0,
        'three' => 0,
        'four' => 0
      },
      'time' => {
        'hammertime' => 50,
        'clobberin_time' => 50
      }
    }
  end
  let(:noop) { -> {} }

  let(:notifier) { instance_double(TestTrack::MisconfigurationNotifier, notify: nil) }

  before do
    allow(TestTrack::MisconfigurationNotifier).to receive(:new).and_return(notifier)
    allow(assignment).to receive(:context=)
  end

  it "isn't defaulted by default" do
    expect(subject.defaulted?).to be_falsey
  end

  context "#initialize" do
    it "raises when given an unknown option" do
      expect do
        described_class.new(
          assignment: assignment,
          split_registry: split_registry,
          context: "the_context",
          one_of_these_things_is_not_like_the_other: "hint: its me!"
        )
      end.to raise_error("unknown opts: one_of_these_things_is_not_like_the_other")
    end

    it "raises when missing a required option" do
      expect do
        described_class.new(
          split_registry: split_registry
        )
      end.to raise_error("Must provide assignment")
    end

    context "when the split is not in the split_registry" do
      let(:assignment) do
        instance_double(TestTrack::Assignment, split_name: "not_a_real_split", variant: "one")
      end

      it "raises a descriptive error" do
        expect do
          described_class.new(
            assignment: assignment,
            split_registry: split_registry,
            context: "the_context"
          )
        end.to raise_error("unknown split: not_a_real_split")
      end
    end
  end

  context "#run" do
    it "tells airbrake if all variants aren't covered" do
      subject.when(:one) { "hello!" }
      subject.default :two, &noop

      expect(subject.send(:run)).to eq "hello!"
      expect(notifier).to have_received(:notify).with("vary for \"button_size\" does not configure variants three and four")
    end

    context "with a nil split_registry" do
      let(:split_registry) { nil }

      before do
        subject.when(:one) { "hello!" }
        subject.default :two, &noop
      end

      it "still runs the correct proc" do
        expect(subject.send(:run)).to eq "hello!"
      end

      it "doesn't alert airbrake about misconfiguration" do
        expect(notifier).not_to have_received(:notify)
      end
    end

    context "with a nil variant" do
      let(:assignment) do
        instance_double(TestTrack::Assignment, split_name: "button_size", variant: nil)
      end

      before do
        subject.when(:one) { "regular" }
        subject.default(:two) { "default" }
      end

      it "runs the default proc and sets the assignment's variant" do
        allow(assignment).to receive(:variant=)

        expect(subject.send(:run)).to eq "default"
        expect(assignment).to have_received(:variant=).with("two")
      end
    end
  end

  context "#when" do
    it "requires at least one variant" do
      expect { subject.when { "huh?" } }.to raise_error("must provide at least one variant")
    end

    it "supports multiple variants" do
      subject.when :one, :two, :three, &noop

      expect(subject.send(:variant_behaviors).size).to eq 3
      expect(subject.send(:variant_behaviors).keys).to eq %w(one two three)
    end

    it "tells airbrake if variant not in registry" do
      subject.when :this_does_not_exist, &noop

      expect(notifier).to have_received(:notify).with('vary for "button_size" configures unknown variant "this_does_not_exist"')
    end

    it "tells airbrake about only invalid variant(s)" do
      subject.when :this_does_not_exist, :two, :three, :and_neither_does_this_one, &noop

      expect(notifier).to have_received(:notify)
        .with('vary for "button_size" configures unknown variant "this_does_not_exist"')
      expect(notifier).to have_received(:notify)
        .with('vary for "button_size" configures unknown variant "and_neither_does_this_one"')
    end

    context "with a nil split_registry" do
      let(:split_registry) { nil }

      it "assumes all variants are valid" do
        subject.when :something_random, &noop

        expect(notifier).not_to have_received(:notify)
      end
    end
  end

  context "#default" do
    it "accepts a block" do
      subject.when :one do
        puts "hello"
      end

      expect(subject.send(:variant_behaviors).size).to eq 1
      expect(subject.send(:variant_behaviors)['one']).to be_a Proc
      expect(subject.send(:variant_behaviors)[:one]).to be_nil
    end

    it "tells airbrake if variant not in registry" do
      subject.default :this_default_does_not_exist, &noop

      expect(notifier).to have_received(:notify)
        .with('vary for "button_size" configures unknown variant "this_default_does_not_exist"')
    end

    context "with a nil split_registry" do
      let(:split_registry) { nil }

      it "assumes all variants are valid" do
        subject.default :something_random, &noop

        expect(notifier).not_to have_received(:notify)
      end
    end
  end
end