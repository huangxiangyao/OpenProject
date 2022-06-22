#-- copyright
# OpenProject is an open source project management software.
# Copyright (C) 2012-2022 the OpenProject GmbH
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# OpenProject is a fork of ChiliProject, which is a fork of Redmine. The copyright follows:
# Copyright (C) 2006-2013 Jean-Philippe Lang
# Copyright (C) 2010-2013 the ChiliProject Team
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# See COPYRIGHT and LICENSE files for more details.
#++

require 'spec_helper'

describe WorkPackages::SetAttributesService, type: :model do
  let(:user) { build_stubbed(:user) }
  let(:project) do
    p = build_stubbed(:project)
    allow(p).to receive(:shared_versions).and_return([])

    p
  end
  let(:work_package) do
    wp = build_stubbed(:work_package, project:)
    wp.type = initial_type
    wp.send(:clear_changes_information)

    wp
  end
  let(:new_work_package) do
    WorkPackage.new
  end
  let(:initial_type) { build_stubbed(:type) }
  let(:statuses) { [] }
  let(:contract_class) { WorkPackages::UpdateContract }
  let(:mock_contract) do
    class_double(contract_class,
                 new: mock_contract_instance)
  end
  let(:mock_contract_instance) do
    instance_double(contract_class,
                    assignable_statuses: statuses,
                    errors: contract_errors,
                    validate: contract_valid)
  end
  let(:contract_valid) { true }
  let(:contract_errors) do
    instance_double(ActiveModel::Errors)
  end
  let(:instance) do
    described_class.new(user:,
                        model: work_package,
                        contract_class: mock_contract)
  end

  shared_examples_for 'service call' do
    subject do
      allow(work_package)
        .to receive(:save)

      instance.call(call_attributes)
    end

    it 'is successful' do
      expect(subject).to be_success
    end

    it 'sets the value' do
      subject

      attributes.each do |attribute, key|
        expect(work_package.send(attribute)).to eql key
      end
    end

    it 'does not persist the work_package' do
      subject

      expect(work_package)
        .not_to have_received(:save)
    end

    it 'has no errors' do
      expect(subject.errors).to be_empty
    end

    context 'when the contract does not validate' do
      let(:contract_valid) { false }

      it 'is unsuccessful' do
        expect(subject).not_to be_success
      end

      it 'does not persist the changes' do
        subject

        expect(work_package)
          .not_to have_received(:save)
      end

      it "exposes the contract's errors" do
        subject

        expect(subject.errors).to eql mock_contract_instance.errors
      end
    end
  end

  context 'when updating subject before calling the service' do
    let(:call_attributes) { {} }
    let(:attributes) { { subject: 'blubs blubs' } }

    before do
      work_package.attributes = attributes
    end

    it_behaves_like 'service call'
  end

  context 'when updating subject via attributes' do
    let(:call_attributes) { attributes }
    let(:attributes) { { subject: 'blubs blubs' } }

    it_behaves_like 'service call'
  end

  context 'for status' do
    let(:default_status) { build_stubbed(:default_status) }
    let(:other_status) { build_stubbed(:status) }
    let(:new_statuses) { [other_status, default_status] }

    before do
      allow(Status)
        .to receive(:default)
              .and_return(default_status)
    end

    context 'with no value set before for a new work package' do
      let(:call_attributes) { {} }
      let(:attributes) { {} }
      let(:work_package) { new_work_package }

      before do
        work_package.status = nil
      end

      it_behaves_like 'service call' do
        it 'sets the default status' do
          subject

          expect(work_package.status)
            .to eql default_status
        end
      end
    end

    context 'with no value set on existing work package' do
      let(:call_attributes) { {} }
      let(:attributes) { {} }

      before do
        work_package.status = nil
      end

      it_behaves_like 'service call' do
        it 'stays nil' do
          subject

          expect(work_package.status)
            .to be_nil
        end
      end
    end

    context 'when updating status before calling the service' do
      let(:call_attributes) { {} }
      let(:attributes) { { status: other_status } }

      before do
        work_package.attributes = attributes
      end

      it_behaves_like 'service call'
    end

    context 'when updating status via attributes' do
      let(:call_attributes) { attributes }
      let(:attributes) { { status: other_status } }

      it_behaves_like 'service call'
    end
  end

  context 'for author' do
    let(:other_user) { build_stubbed(:user) }

    context 'with no value set before for a new work package' do
      let(:call_attributes) { {} }
      let(:attributes) { {} }
      let(:work_package) { new_work_package }

      it_behaves_like 'service call' do
        it "sets the service's author" do
          subject

          expect(work_package.author)
            .to eql user
        end

        it 'notes the author to be system changed' do
          subject

          expect(work_package.changed_by_system['author_id'])
            .to eql [0, user.id]
        end
      end
    end

    context 'with no value set on existing work package' do
      let(:call_attributes) { {} }
      let(:attributes) { {} }

      before do
        work_package.author = nil
      end

      it_behaves_like 'service call' do
        it 'stays nil' do
          subject

          expect(work_package.author)
            .to be_nil
        end
      end
    end

    context 'when updating author before calling the service' do
      let(:call_attributes) { {} }
      let(:attributes) { { author: other_user } }

      before do
        work_package.attributes = attributes
      end

      it_behaves_like 'service call'
    end

    context 'when updating author via attributes' do
      let(:call_attributes) { attributes }
      let(:attributes) { { author: other_user } }

      it_behaves_like 'service call'
    end
  end

  context 'with the actual contract' do
    let(:invalid_wp) do
      wp = create(:work_package)
      wp.start_date = Time.zone.today + 5.days
      wp.due_date = Time.zone.today
      wp.save!(validate: false)

      wp
    end
    let(:user) { build_stubbed(:admin) }
    let(:instance) do
      described_class.new(user:,
                          model: invalid_wp,
                          contract_class:)
    end

    context 'with a current invalid start date' do
      let(:call_attributes) { attributes }
      let(:attributes) { { start_date: Time.zone.today - 5.days } }
      let(:contract_valid) { true }

      subject { instance.call(call_attributes) }

      it 'is successful' do
        expect(subject).to be_success
        expect(subject.errors).to be_empty
      end
    end
  end

  context 'for start_date & due_date & duration' do
    context 'with a parent' do
      let(:attributes) { {} }
      let(:work_package) { new_work_package }
      let(:parent) do
        build_stubbed(:work_package,
                      start_date: parent_start_date,
                      due_date: parent_due_date)
      end
      let(:parent_start_date) { Time.zone.today - 5.days }
      let(:parent_due_date) { Time.zone.today + 10.days }

      context 'with the parent having dates and not providing own dates' do
        let(:call_attributes) { { parent: } }

        it_behaves_like 'service call' do
          it "sets the start_date to the parent`s start_date" do
            subject

            expect(work_package.start_date)
              .to eql parent_start_date
          end

          it "sets the due_date to the parent`s due_date" do
            subject

            expect(work_package.due_date)
              .to eql parent_due_date
          end
        end
      end

      context 'with the parent having start date (no due) and not providing own dates' do
        let(:call_attributes) { { parent: } }
        let(:parent_due_date) { nil }

        it_behaves_like 'service call' do
          it "sets the start_date to the parent`s start_date" do
            subject

            expect(work_package.start_date)
              .to eql parent_start_date
          end

          it "sets the due_date to nil" do
            subject

            expect(work_package.due_date)
              .to be_nil
          end
        end
      end

      context 'with the parent having due date (no start) and not providing own dates' do
        let(:call_attributes) { { parent: } }
        let(:parent_start_date) { nil }

        it_behaves_like 'service call' do
          it "sets the start_date to nil" do
            subject

            expect(work_package.start_date)
              .to be_nil
          end

          it "sets the due_date to the parent`s due_date" do
            subject

            expect(work_package.due_date)
              .to eql parent_due_date
          end
        end
      end

      context 'with the parent having dates but providing own dates' do
        let(:call_attributes) { { parent:, start_date: Time.zone.today, due_date: Time.zone.today + 1.day } }

        it_behaves_like 'service call' do
          it "sets the start_date to the provided date" do
            subject

            expect(work_package.start_date)
              .to eql Time.zone.today
          end

          it "sets the due_date to the provided date" do
            subject

            expect(work_package.due_date)
              .to eql Time.zone.today + 1.day
          end
        end
      end

      context 'with the parent having dates but providing own start_date' do
        let(:call_attributes) { { parent:, start_date: Time.zone.today } }

        it_behaves_like 'service call' do
          it "sets the start_date to the provided date" do
            subject

            expect(work_package.start_date)
              .to eql Time.zone.today
          end

          it "sets the due_date to the parent's due_date" do
            subject

            expect(work_package.due_date)
              .to eql parent_due_date
          end
        end
      end

      context 'with the parent having dates but providing own due_date' do
        let(:call_attributes) { { parent:, due_date: Time.zone.today + 4.days } }

        it_behaves_like 'service call' do
          it "sets the start_date to the parent's start date" do
            subject

            expect(work_package.start_date)
              .to eql parent_start_date
          end

          it "sets the due_date to the provided date" do
            subject

            expect(work_package.due_date)
              .to eql Time.zone.today + 4.days
          end
        end
      end

      context 'with the parent having dates but providing own empty start_date' do
        let(:call_attributes) { { parent:, start_date: nil } }

        it_behaves_like 'service call' do
          it "sets the start_date to nil" do
            subject

            expect(work_package.start_date)
              .to be_nil
          end

          it "sets the due_date to the parent's due_date" do
            subject

            expect(work_package.due_date)
              .to eql parent_due_date
          end
        end
      end

      context 'with the parent having dates but providing own empty due_date' do
        let(:call_attributes) { { parent:, due_date: nil } }

        it_behaves_like 'service call' do
          it "sets the start_date to the parent's start date" do
            subject

            expect(work_package.start_date)
              .to eql parent_start_date
          end

          it "sets the due_date to nil" do
            subject

            expect(work_package.due_date)
              .to be_nil
          end
        end
      end

      context 'with the parent having dates but providing a start date that is before parent`s due date`' do
        let(:call_attributes) { { parent:, start_date: parent_due_date - 4.days } }

        it_behaves_like 'service call' do
          it "sets the start_date to the provided date" do
            subject

            expect(work_package.start_date)
              .to eql parent_due_date - 4.days
          end

          it "sets the due_date to the parent's due_date" do
            subject

            expect(work_package.due_date)
              .to eql parent_due_date
          end
        end
      end

      context 'with the parent having dates but providing a start date that is after the parent`s due date`' do
        let(:call_attributes) { { parent:, start_date: parent_due_date + 1.day } }

        it_behaves_like 'service call' do
          it "sets the start_date to the provided date" do
            subject

            expect(work_package.start_date)
              .to eql parent_due_date + 1.day
          end

          it "leaves the due date empty" do
            subject

            expect(work_package.due_date)
              .to be_nil
          end
        end
      end

      context 'with the parent having dates but providing a due date that is before the parent`s start date`' do
        let(:call_attributes) { { parent:, due_date: parent_start_date - 3.days } }

        it_behaves_like 'service call' do
          it "leaves the start date empty" do
            subject

            expect(work_package.start_date)
              .to be_nil
          end

          it "set the due date to the provided date" do
            subject

            expect(work_package.due_date)
              .to eql parent_start_date - 3.days
          end
        end
      end
    end

    context 'with no value set for a new work package and with default setting active',
            with_settings: { work_package_startdate_is_adddate: true } do
      let(:call_attributes) { {} }
      let(:attributes) { {} }
      let(:work_package) { new_work_package }

      it_behaves_like 'service call' do
        it "sets the start date to today" do
          subject

          expect(work_package.start_date)
            .to eql Time.zone.today
        end

        it "sets the duration to nil" do
          subject

          expect(work_package.duration)
            .to be_nil
        end
      end
    end

    context 'with a value set for a new work package and with default setting active',
            with_settings: { work_package_startdate_is_adddate: true } do
      let(:call_attributes) { { start_date: Time.zone.today + 1.day } }
      let(:attributes) { {} }
      let(:work_package) { new_work_package }

      it_behaves_like 'service call' do
        it 'stays that value' do
          subject

          expect(work_package.start_date)
            .to eq(Time.zone.today + 1.day)
        end

        it "sets the duration to nil" do
          subject

          expect(work_package.duration)
            .to be_nil
        end
      end
    end

    context 'with date values set to the same date on a new work package' do
      let(:call_attributes) { { start_date: Time.zone.today, due_date: Time.zone.today } }
      let(:attributes) { {} }
      let(:work_package) { new_work_package }

      it_behaves_like 'service call' do
        it 'sets the start date value' do
          subject

          expect(work_package.start_date)
            .to eq(Time.zone.today)
        end

        it 'sets the due date value' do
          subject

          expect(work_package.due_date)
            .to eq(Time.zone.today)
        end

        it "sets the duration to 1" do
          subject

          expect(work_package.duration)
            .to eq 1
        end
      end
    end

    context 'with date values set on a new work package' do
      let(:call_attributes) { { start_date: Time.zone.today, due_date: Time.zone.today + 5.days } }
      let(:attributes) { {} }
      let(:work_package) { new_work_package }

      it_behaves_like 'service call' do
        it 'sets the start date value' do
          subject

          expect(work_package.start_date)
            .to eq(Time.zone.today)
        end

        it 'sets the due date value' do
          subject

          expect(work_package.due_date)
            .to eq(Time.zone.today + 5.days)
        end

        it "sets the duration to 6" do
          subject

          expect(work_package.duration)
            .to eq 6
        end
      end
    end

    context 'with start date changed' do
      let(:work_package) { build_stubbed(:work_package, start_date: Time.zone.today, due_date: Time.zone.today + 5.days) }
      let(:call_attributes) { { start_date: Time.zone.today + 1.day } }
      let(:attributes) { {} }

      it_behaves_like 'service call' do
        it 'sets the start date value' do
          subject

          expect(work_package.start_date)
            .to eq(Time.zone.today + 1.day)
        end

        it 'keeps the due date value' do
          subject

          expect(work_package.due_date)
            .to eq(Time.zone.today + 5.days)
        end

        it "updates the duration" do
          subject

          expect(work_package.duration)
            .to eq 5
        end
      end
    end

    context 'with due date changed' do
      let(:work_package) { build_stubbed(:work_package, start_date: Time.zone.today, due_date: Time.zone.today + 5.days) }
      let(:call_attributes) { { due_date: Time.zone.today + 1.day } }
      let(:attributes) { {} }

      it_behaves_like 'service call' do
        it 'keeps the start date value' do
          subject

          expect(work_package.start_date)
            .to eq(Time.zone.today)
        end

        it 'sets the due date value' do
          subject

          expect(work_package.due_date)
            .to eq(Time.zone.today + 1.day)
        end

        it "updates the duration" do
          subject

          expect(work_package.duration)
            .to eq 2
        end
      end
    end

    context 'with start date nilled' do
      let(:work_package) { build_stubbed(:work_package, start_date: Time.zone.today, due_date: Time.zone.today + 5.days) }
      let(:call_attributes) { { start_date: nil } }
      let(:attributes) { {} }

      it_behaves_like 'service call' do
        it 'sets the start date to nil' do
          subject

          expect(work_package.start_date)
            .to be_nil
        end

        it 'keeps the due date value' do
          subject

          expect(work_package.due_date)
            .to eq(Time.zone.today + 5.days)
        end

        it "sets the duration to nil" do
          subject

          expect(work_package.duration)
            .to be_nil
        end
      end
    end

    context 'with due date nilled' do
      let(:work_package) { build_stubbed(:work_package, start_date: Time.zone.today, due_date: Time.zone.today + 5.days) }
      let(:call_attributes) { { due_date: nil } }
      let(:attributes) { {} }

      it_behaves_like 'service call' do
        it 'keeps the start date' do
          subject

          expect(work_package.start_date)
            .to eq(Time.zone.today)
        end

        it 'nils the due date' do
          subject

          expect(work_package.due_date)
            .to be_nil
        end

        it "sets the duration to nil" do
          subject

          expect(work_package.duration)
            .to be_nil
        end
      end
    end

    context 'with duration explicitly set' do
      let(:work_package) { build_stubbed(:work_package, start_date: Time.zone.today, due_date: Time.zone.today + 5.days) }
      let(:call_attributes) { { due_date: Time.zone.today + 2.days, duration: 8 } }
      let(:attributes) { {} }

      it_behaves_like 'service call' do
        it 'keeps the start date' do
          subject

          expect(work_package.start_date)
            .to eq(Time.zone.today)
        end

        it 'sets the due date' do
          subject

          expect(work_package.due_date)
            .to eq(Time.zone.today + 2.days)
        end

        it "sets the faulty duration (for error reporting)" do
          subject

          expect(work_package.duration)
            .to eq 8
        end
      end
    end
  end

  context 'for priority' do
    let(:default_priority) { build_stubbed(:priority) }
    let(:other_priority) { build_stubbed(:priority) }

    before do
      scope = class_double(IssuePriority)

      allow(IssuePriority)
        .to receive(:active)
              .and_return(scope)
      allow(scope)
        .to receive(:default)
              .and_return(default_priority)
    end

    context 'with no value set before for a new work package' do
      let(:call_attributes) { {} }
      let(:attributes) { {} }
      let(:work_package) { new_work_package }

      before do
        work_package.priority = nil
      end

      it_behaves_like 'service call' do
        it "sets the default priority" do
          subject

          expect(work_package.priority)
            .to eql default_priority
        end
      end
    end

    context 'when updating priority before calling the service' do
      let(:call_attributes) { {} }
      let(:attributes) { { priority: other_priority } }

      before do
        work_package.attributes = attributes
      end

      it_behaves_like 'service call'
    end

    context 'when updating priority via attributes' do
      let(:call_attributes) { attributes }
      let(:attributes) { { priority: other_priority } }

      it_behaves_like 'service call'
    end
  end

  context 'when switching the type' do
    let(:target_type) { build_stubbed(:type) }
    let(:work_package) do
      build_stubbed(:work_package, start_date: Time.zone.today - 6.days, due_date: Time.zone.today)
    end

    context 'with a type that is no milestone' do
      before do
        allow(target_type)
          .to receive(:is_milestone?)
                .and_return(false)
      end

      it 'keeps the start date' do
        instance.call(type: target_type)

        expect(work_package.start_date)
          .to eql Time.zone.today - 6.days
      end

      it 'keeps the due date' do
        instance.call(type: target_type)

        expect(work_package.due_date)
          .to eql Time.zone.today
      end

      it 'keeps duration' do
        instance.call(type: target_type)

        expect(work_package.duration).to be 7
      end
    end

    context 'with a type that is a milestone and with both dates set' do
      before do
        allow(target_type)
          .to receive(:is_milestone?)
                .and_return(true)
      end

      it 'sets the start date to the due date' do
        instance.call(type: target_type)

        expect(work_package.start_date).to eql Time.zone.today
      end

      it 'keeps the due date' do
        instance.call(type: target_type)

        expect(work_package.due_date).to eql Time.zone.today
      end

      it 'sets the duration to 1 (to be changed to 0 later on)' do
        instance.call(type: target_type)

        expect(work_package.duration).to eq 1
      end
    end

    context 'with a type that is a milestone and with only the start date set' do
      let(:work_package) do
        build_stubbed(:work_package, start_date: Time.zone.today - 6.days)
      end

      before do
        allow(target_type)
          .to receive(:is_milestone?)
                .and_return(true)
      end

      it 'keeps the start date' do
        instance.call(type: target_type)

        expect(work_package.start_date).to eql Time.zone.today - 6.days
      end

      it 'set the due date to the start date' do
        instance.call(type: target_type)

        expect(work_package.due_date).to eql Time.zone.today - 6.days
      end

      it 'keeps the duration at 1 (to be changed to 0 later on)' do
        instance.call(type: target_type)

        expect(work_package.duration).to eq 1
      end
    end
  end

  context 'when switching the project' do
    let(:new_project) { build_stubbed(:project) }
    let(:version) { build_stubbed(:version) }
    let(:category) { build_stubbed(:category) }
    let(:new_category) { build_stubbed(:category, name: category.name) }
    let(:new_statuses) { [work_package.status] }
    let(:new_versions) { [] }
    let(:type) { work_package.type }
    let(:new_types) { [type] }
    let(:default_type) { build_stubbed(:type_standard) }
    let(:other_type) { build_stubbed(:type) }
    let(:yet_another_type) { build_stubbed(:type) }

    let(:call_attributes) { {} }
    let(:new_project_categories) do
      instance_double(ActiveRecord::Relation).tap do |categories_stub|
        allow(new_project)
          .to receive(:categories)
                .and_return(categories_stub)
      end
    end

    before do
      allow(new_project)
        .to receive(:shared_versions)
              .and_return(new_versions)
      allow(new_project_categories)
        .to receive(:find_by)
              .with(name: category.name)
              .and_return nil
      allow(new_project)
        .to receive(:types)
              .and_return(new_types)
      allow(new_types)
        .to receive(:order)
              .with(:position)
              .and_return(new_types)
    end

    shared_examples_for 'updating the project' do
      context 'for version' do
        before do
          work_package.version = version
        end

        context 'when not shared in new project' do
          it 'sets to nil' do
            subject

            expect(work_package.version)
              .to be_nil
          end
        end

        context 'when shared in the new project' do
          let(:new_versions) { [version] }

          it 'keeps the version' do
            subject

            expect(work_package.version)
              .to eql version
          end
        end
      end

      context 'for category' do
        before do
          work_package.category = category
        end

        context 'when no category of same name in new project' do
          it 'sets to nil' do
            subject

            expect(work_package.category)
              .to be_nil
          end
        end

        context 'when category of same name in new project' do
          before do
            allow(new_project_categories)
              .to receive(:find_by)
                    .with(name: category.name)
                    .and_return new_category
          end

          it 'uses the equally named category' do
            subject

            expect(work_package.category)
              .to eql new_category
          end

          it 'adds change to system changes' do
            subject

            expect(work_package.changed_by_system['category_id'])
              .to eql [nil, new_category.id]
          end
        end
      end

      context 'for type' do
        context 'when current type exists in new project' do
          it 'leaves the type' do
            subject

            expect(work_package.type)
              .to eql type
          end
        end

        context 'when a default type exists in new project' do
          let(:new_types) { [other_type, default_type] }

          it 'uses the first type (by position)' do
            subject

            expect(work_package.type)
              .to eql other_type
          end

          it 'adds change to system changes' do
            subject

            expect(work_package.changed_by_system['type_id'])
              .to eql [initial_type.id, other_type.id]
          end
        end

        context 'when no default type exists in new project' do
          let(:new_types) { [other_type, yet_another_type] }

          it 'uses the first type (by position)' do
            subject

            expect(work_package.type)
              .to eql other_type
          end

          it 'adds change to system changes' do
            subject

            expect(work_package.changed_by_system['type_id'])
              .to eql [initial_type.id, other_type.id]
          end
        end

        context 'when also setting a new type via attributes' do
          let(:attributes) { { project: new_project, type: yet_another_type } }

          it 'sets the desired type' do
            subject

            expect(work_package.type)
              .to eql yet_another_type
          end

          it 'does not set the change to system changes' do
            subject

            expect(work_package.changed_by_system)
              .not_to include('type_id')
          end
        end
      end

      context 'for parent' do
        let(:parent_work_package) { build_stubbed(:work_package, project:) }
        let(:work_package) do
          build_stubbed(:work_package, project:, type: initial_type, parent: parent_work_package)
        end

        context 'with cross project relations allowed', with_settings: { cross_project_work_package_relations: true } do
          it 'keeps the parent' do
            expect(subject)
              .to be_success

            expect(work_package.parent)
              .to eql(parent_work_package)
          end
        end

        context 'with cross project relations disabled', with_settings: { cross_project_work_package_relations: false } do
          it 'deletes the parent' do
            expect(subject)
              .to be_success

            expect(work_package.parent)
              .to be_nil
          end
        end
      end
    end

    context 'when updating project before calling the service' do
      let(:call_attributes) { {} }
      let(:attributes) { { project: new_project } }

      before do
        work_package.attributes = attributes
      end

      it_behaves_like 'service call' do
        it_behaves_like 'updating the project'
      end
    end

    context 'when updating project via attributes' do
      let(:call_attributes) { attributes }
      let(:attributes) { { project: new_project } }

      it_behaves_like 'service call' do
        it_behaves_like 'updating the project'
      end
    end
  end

  context 'for custom fields' do
    subject { instance.call(call_attributes) }

    context 'for non existing fields' do
      let(:call_attributes) { { custom_field_891: '1' } } # rubocop:disable Naming/VariableNumber

      before do
        subject
      end

      it 'is successful' do
        expect(subject).to be_success
      end
    end
  end

  context 'when switching back to automatic scheduling' do
    let(:work_package) do
      wp = build_stubbed(:work_package,
                         project:,
                         schedule_manually: true,
                         start_date: Time.zone.today,
                         due_date: Time.zone.today + 5.days)
      wp.type = build_stubbed(:type)
      wp.send(:clear_changes_information)

      allow(wp)
        .to receive(:soonest_start)
              .and_return(soonest_start)

      wp
    end
    let(:call_attributes) { { schedule_manually: false } }
    let(:attributes) { {} }
    let(:soonest_start) { Time.zone.today + 1.day }

    context 'when the soonest start date is later than the current start date' do
      let(:soonest_start) { Time.zone.today + 3.days }

      it_behaves_like 'service call' do
        it 'sets the start date to the soonest possible start date' do
          subject

          expect(work_package.start_date).to eql(Time.zone.today + 3.days)
          expect(work_package.due_date).to eql(Time.zone.today + 8.days)
        end
      end
    end

    context 'when the soonest start date is before the current start date' do
      let(:soonest_start) { Time.zone.today - 3.days }

      it_behaves_like 'service call' do
        it 'sets the start date to the soonest possible start date' do
          subject

          expect(work_package.start_date).to eql(soonest_start)
          expect(work_package.due_date).to eql(Time.zone.today + 2.days)
        end
      end
    end

    context 'when the soonest start date is nil' do
      let(:soonest_start) { nil }

      it_behaves_like 'service call' do
        it 'sets the start date to the soonest possible start date' do
          subject

          expect(work_package.start_date).to eql(Time.zone.today)
          expect(work_package.due_date).to eql(Time.zone.today + 5.days)
        end
      end
    end

    context 'when the work package also has a child' do
      let(:child) do
        build_stubbed(:work_package,
                      start_date: child_start_date,
                      due_date: child_due_date)
      end
      let(:child_start_date) { Time.zone.today + 2.days }
      let(:child_due_date) { Time.zone.today + 10.days }

      before do
        allow(work_package)
          .to receive(:children)
                .and_return([child])
      end

      context 'when the child`s start date is after soonest_start' do
        it_behaves_like 'service call' do
          it 'sets the dates to the child dates' do
            subject

            expect(work_package.start_date).to eql(Time.zone.today + 2.days)
            expect(work_package.due_date).to eql(Time.zone.today + 10.days)
          end
        end
      end

      context 'when the child`s start date is before soonest_start' do
        let(:soonest_start) { Time.zone.today + 3.days }

        it_behaves_like 'service call' do
          it 'sets the dates to soonest date and to the duration of the child' do
            subject

            expect(work_package.start_date).to eql(Time.zone.today + 3.days)
            expect(work_package.due_date).to eql(Time.zone.today + 11.days)
          end
        end
      end
    end
  end
end
