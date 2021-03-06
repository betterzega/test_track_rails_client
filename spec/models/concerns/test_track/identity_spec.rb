require 'rails_helper'

RSpec.describe TestTrack::Identity do
  TestTrack::ClownModel = Class.new do
    include ActiveModel::Model
    include TestTrack::Identity

    test_track_identifier "clown_id", :id

    def id
      1234
    end
  end

  let(:test_track_controller_class) do
    Class.new(ApplicationController) { include TestTrack::Controller }
  end

  let(:test_track_controller) { test_track_controller_class.new }

  subject { TestTrack::ClownModel.new }

  describe ".test_track_identifier" do
    let(:unsynced_assignments_notifier) { instance_double(TestTrack::UnsyncedAssignmentsNotifier, notify: true) }

    before do
      allow(TestTrack::OfflineSession).to receive(:with_visitor_for).and_call_original
      allow(TestTrack::VisitorDSL).to receive(:new).and_call_original
      allow(TestTrack::UnsyncedAssignmentsNotifier).to receive(:new).and_return(unsynced_assignments_notifier)
      allow(TestTrack::Remote::SplitRegistry).to receive(:to_hash).and_return(
        "blue_button" => { "true" => 0, "false" => 100 },
        "side_dish" => { "soup" => 0, "salad" => 100 }
      )
    end

    context "#test_track_ab" do
      context "in a web request" do
        let(:visitor) { TestTrack::Visitor.new }
        let(:visitor_dsl) { TestTrack::VisitorDSL.new(visitor) }

        before do
          allow(RequestStore).to receive(:exist?).and_return(true)
          allow(RequestStore).to receive(:[]).with(:test_track_controller).and_return(test_track_controller)
          allow(test_track_controller).to receive(:test_track_visitor).and_return(visitor_dsl)
          allow(visitor).to receive(:ab).and_call_original
        end

        it "returns the correct value" do
          expect(subject.test_track_ab(:blue_button, context: :spec)).to be false
        end

        context "controller does not have a #current_* method" do
          it "uses an offline session" do
            subject.test_track_ab(:blue_button, context: :spec)
            expect(TestTrack::OfflineSession).to have_received(:with_visitor_for)
          end
        end

        context "controller has a #current_* method" do
          let(:test_track_controller_class) do
            Class.new(ApplicationController) do
              include TestTrack::Controller

              private # make current_clown_model private to better simulate real world scenario

              def current_clown_model
              end
            end
          end

          context "current_* equals the subject" do
            before do
              allow(test_track_controller).to receive(:current_clown_model).and_return(subject)
            end

            it "does not create an offline session" do
              subject.test_track_ab(:blue_button, context: :spec)
              expect(TestTrack::OfflineSession).not_to have_received(:with_visitor_for)
            end

            it "forwards all arguments to the visitor correctly" do
              subject.test_track_ab(:side_dish, true_variant: "soup", context: :spec)
              expect(visitor).to have_received(:ab).with(:side_dish, true_variant: "soup", context: :spec)
            end

            it "does not send notifications inline" do
              subject.test_track_ab(:blue_button, context: :spec)
              expect(TestTrack::UnsyncedAssignmentsNotifier).not_to have_received(:new)
            end

            it "appends the assignment to the visitor's unsynced assignments" do
              subject.test_track_ab(:blue_button, context: :spec)
              visitor.unsynced_assignments.first.tap do |assignment|
                expect(assignment.split_name).to eq("blue_button")
                expect(assignment.variant).to eq("false")
              end
            end
          end

          context "current_* does not equal the subject" do
            before do
              allow(test_track_controller).to receive(:current_clown_model).and_return(TestTrack::ClownModel.new)
            end

            it "uses an offline session" do
              subject.test_track_ab(:blue_button, context: :spec)
              expect(TestTrack::OfflineSession).to have_received(:with_visitor_for)
            end
          end
        end
      end

      context "not in a web request" do
        let(:visitor) { TestTrack::Visitor.new(id: "fake_visitor_id") }

        before do
          allow(TestTrack::Visitor).to receive(:new).and_return(visitor)
          allow(visitor).to receive(:ab).and_call_original
        end

        it "returns the correct value" do
          expect(subject.test_track_ab(:blue_button, context: :spec)).to be false
        end

        it "forwards all arguments to the visitor correctly" do
          subject.test_track_ab(:side_dish, true_variant: "soup", context: :spec)
          expect(visitor).to have_received(:ab).with(:side_dish, true_variant: "soup", context: :spec)
        end

        it "creates an offline session" do
          subject.test_track_ab :blue_button, context: :spec
          expect(TestTrack::OfflineSession).to have_received(:with_visitor_for).with("clown_id", 1234)
        end

        it "sends notifications inline" do
          subject.test_track_ab :blue_button, context: :spec
          expect(TestTrack::UnsyncedAssignmentsNotifier).to have_received(:new) do |args|
            expect(args[:visitor_id]).to eq("fake_visitor_id")
            args[:assignments].first.tap do |assignment|
              expect(assignment.split_name).to eq("blue_button")
              expect(assignment.variant).to eq("false")
            end
          end
        end
      end
    end

    context "#test_track_vary" do
      def vary_side_dish
        subject.test_track_vary(:side_dish, context: :spec) do |v|
          v.when(:soup) { "soups on" }
          v.default(:salad) { "salad please" }
        end
      end

      context "in a web request" do
        let(:visitor) { TestTrack::Visitor.new }
        let(:visitor_dsl) { TestTrack::VisitorDSL.new(visitor) }

        before do
          allow(RequestStore).to receive(:exist?).and_return(true)
          allow(RequestStore).to receive(:[]).with(:test_track_controller).and_return(test_track_controller)
          allow(test_track_controller).to receive(:test_track_visitor).and_return(visitor_dsl)
        end

        it "returns the correct value" do
          expect(vary_side_dish).to eq "salad please"
        end

        context "controller does not have a #current_* method" do
          it "uses an offline session" do
            vary_side_dish
            expect(TestTrack::OfflineSession).to have_received(:with_visitor_for)
          end
        end

        context "controller has a #current_* method" do
          let(:test_track_controller_class) do
            Class.new(ApplicationController) do
              include TestTrack::Controller

              private # make current_clown_model private to better simulate real world scenario

              def current_clown_model
              end
            end
          end

          context "current_* equals the subject" do
            before do
              allow(test_track_controller).to receive(:current_clown_model).and_return(subject)
            end

            it "does not create an offline session" do
              vary_side_dish
              expect(TestTrack::OfflineSession).not_to have_received(:with_visitor_for)
            end

            it "does not send notifications inline" do
              vary_side_dish
              expect(TestTrack::UnsyncedAssignmentsNotifier).not_to have_received(:new)
            end

            it "appends the assignment to the visitor's unsynced assignments" do
              vary_side_dish
              visitor.unsynced_assignments.first.tap do |assignment|
                expect(assignment.split_name).to eq("side_dish")
                expect(assignment.variant).to eq("salad")
              end
            end
          end

          context "current_* does not equal the subject" do
            before do
              allow(test_track_controller).to receive(:current_clown_model).and_return(TestTrack::ClownModel.new)
            end

            it "uses an offline session" do
              vary_side_dish
              expect(TestTrack::OfflineSession).to have_received(:with_visitor_for)
            end
          end
        end
      end

      context "not in a web request" do
        it "returns the correct value" do
          expect(vary_side_dish).to eq "salad please"
        end

        it "creates an offline session" do
          vary_side_dish
          expect(TestTrack::OfflineSession).to have_received(:with_visitor_for).with("clown_id", 1234)
        end

        it "sends notifications inline" do
          vary_side_dish
          expect(TestTrack::UnsyncedAssignmentsNotifier).to have_received(:new) do |args|
            expect(args[:visitor_id]).to eq("fake_visitor_id")
            args[:assignments].first.tap do |assignment|
              expect(assignment.split_name).to eq("side_dish")
              expect(assignment.variant).to eq("salad")
            end
          end
        end
      end
    end

    context "#test_track_visitor_id" do
      context "in an offline session" do
        it "returns the correct value" do
          expect(subject.test_track_visitor_id).to eq 'fake_visitor_id'
        end
      end

      context "in a web context" do
        let(:visitor) { TestTrack::Visitor.new }
        let(:visitor_dsl) { TestTrack::VisitorDSL.new(visitor) }

        before do
          allow(RequestStore).to receive(:exist?).and_return true
          allow(RequestStore).to receive(:[]).with(:test_track_controller).and_return test_track_controller
          allow(test_track_controller).to receive(:test_track_visitor).and_return visitor_dsl
        end

        it "returns the correct value" do
          expect(subject.test_track_visitor_id).to eq 'fake_visitor_id'
        end
      end
    end

    context "#test_track_sign_up!" do
      context "in an offline session" do
        it "raises" do
          expect { subject.test_track_sign_up! }.to raise_error /called outside of a web context/
        end
      end

      context "in a web context" do
        let(:session) { TestTrack::Session.new(test_track_controller) }

        it "signs up using the online session" do
          allow(RequestStore).to receive(:exist?).and_return true
          allow(RequestStore).to receive(:[]).with(:test_track_controller).and_return test_track_controller
          allow(session).to receive(:sign_up!)
          allow(test_track_controller).to receive(:test_track_session).and_return(session)

          subject.test_track_sign_up!

          expect(test_track_controller).to have_received(:test_track_session)
          expect(session).to have_received(:sign_up!).with("clown_id", 1234)
        end
      end
    end

    context "#test_track_log_in!" do
      context "in an offline session" do
        it "raises" do
          expect { subject.test_track_log_in! }.to raise_error /called outside of a web context/
        end
      end

      context "in a web context" do
        let(:session) { TestTrack::Session.new(test_track_controller) }

        it "signs up using the online session" do
          allow(RequestStore).to receive(:exist?).and_return true
          allow(RequestStore).to receive(:[]).with(:test_track_controller).and_return test_track_controller
          allow(session).to receive(:log_in!)
          allow(test_track_controller).to receive(:test_track_session).and_return(session)

          subject.test_track_log_in!

          expect(test_track_controller).to have_received(:test_track_session)
          expect(session).to have_received(:log_in!).with("clown_id", 1234, {})
        end
      end
    end
  end
end
