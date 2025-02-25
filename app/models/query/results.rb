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

class ::Query::Results
  include ::Query::Results::GroupBy
  include ::Query::Results::Sums
  include Redmine::I18n

  attr_accessor :query

  def initialize(query)
    self.query = query
  end

  # Returns the work package count
  def work_package_count
    work_package_scope
      .joins(all_filter_joins)
      .includes(:project)
      .where(query.statement)
      .references(:projects)
      .count
  rescue ::ActiveRecord::StatementInvalid => e
    raise ::Query::StatementInvalid.new(e.message)
  end

  # Returns the work packages adhering to the filters and ordered by the provided criteria (grouping and sorting)
  def work_packages
    work_package_scope
      .where(query.statement)
      .includes(all_includes)
      .joins(all_joins)
      .order(order_option)
      .references(:projects)
      .order(sort_criteria_array)
  end

  def order_option
    order_option = [group_by_sort].compact_blank.join(', ')

    if order_option.blank?
      nil
    else
      Arel.sql(order_option)
    end
  end

  private

  def work_package_scope
    WorkPackage
      .visible
      .merge(filter_merges)
  end

  def all_includes
    (%i(project) +
      includes_for_columns(include_columns)).uniq
  end

  def all_joins
    sort_criteria_joins + all_filter_joins
  end

  def includes_for_columns(column_names)
    column_names = Array(column_names)
    (WorkPackage.reflections.keys.map(&:to_sym) & column_names.map(&:to_sym))
  end

  def custom_field_column?(name)
    name.to_s =~ /\Acf_\d+\z/
  end

  ##
  # Returns the columns that need to be included to allow:
  # * sorting
  # * grouping
  def include_columns
    columns = query.sort_criteria_columns.map { |column, _direction| column.association }

    if query.group_by_column
      columns << query.group_by_column.association
    end

    columns << all_filter_includes(query)

    clean_symbol_list(columns)
  end

  def sort_criteria_joins
    query
      .sort_criteria_columns
      .map { |column, _direction| column.sortable_join_statement(query) }
      .compact
  end

  def sort_criteria_array
    criteria = ::Query::SortCriteria.new query.sortable_columns
    criteria.available_criteria = aliased_sorting_by_column_name
    criteria.criteria = query.sort_criteria
    criteria.map_each { |c| c.map { |raw| Arel.sql raw } }
  end

  def aliased_sorting_by_column_name
    sorting_by_column_name = query.sortable_key_by_column_name
    aliases = include_aliases
    reflections = reflection_includes

    sorting_by_column_name.each_with_object({}) do |(column_key, sortable), hash|
      column_is_association = reflections.include?(column_key.to_sym)
      columns_hash = columns_hash_for(column_is_association ? column_key : nil)
      hash[column_key] = if column_is_association
                           alias_name = aliases[column_key.to_sym]
                           expand_association_columns(alias_name, sortable, columns_hash)
                         else
                           case_insensitive_condition(column_key, sortable, columns_hash)
                         end
    end
  end

  ##
  # Returns the expanded association columns name
  def expand_association_columns(alias_name, sortable, columns_hash)
    Array(sortable).map do |column|
      sort_condition = expand_association_column(column, alias_name)
      case_insensitive_condition(column, sort_condition, columns_hash)
    end
  end

  ##
  # Returns a single expanded association column name
  def expand_association_column(column, alias_name)
    if column.respond_to?(:call)
      column.call(alias_name)
    else
      "#{alias_name}.#{column}"
    end
  end

  ##
  # Return the columns hash for a given association
  # If the association is nil, then return the WorkPackage.columns_hash
  def columns_hash_for(association = nil)
    if association
      WorkPackage.reflections[association].klass.columns_hash
    else
      WorkPackage.columns_hash
    end
  end

  ##
  # Return the case insensitive version for columns with a string type
  def case_insensitive_condition(column_key, condition, columns_hash)
    if columns_hash[column_key]&.type == :string
      "LOWER(#{condition})"
    elsif custom_field_type(column_key) == "string"
      condition.map { |c| "LOWER(#{c})" }
    else
      condition
    end
  end

  ##
  # Find the custom field type based on the column key
  def custom_field_type(column_key)
    (column = query.sortable_columns.detect { |c| c.name.to_s == column_key }) &&
    column.respond_to?(:custom_field) &&
    column.custom_field.field_format
  end

  # To avoid naming conflicts, joined tables are aliased if they are joined
  # more than once. Here, joining tables that are referenced by multiple
  # columns are of particular interest.
  #
  # Mirroring the way AR creates aliases for included/joined tables: Normally,
  # included/joined associations are not aliased and as such, they simply use
  # the table name. But if an association is joined/included that relies on a
  # table which an already joined/included association also relies upon, that
  # name is already taken in the DB query. Therefore, the #alias_candidate
  # method is used which will concatenate the pluralized association name with
  # the table name the association is defined for.
  #
  # There is no handling for cases when the same association is joined/included
  # multiple times as the rest of the code should prevent that.
  def include_aliases
    counts = Hash.new do |h, key|
      h[key] = 0
    end

    reflection_includes.each_with_object({}) do |inc, hash|
      reflection = WorkPackage.reflections[inc.to_s]
      table_name = reflection.klass.table_name

      hash[inc] = reflection_alias(reflection, counts[table_name])

      counts[table_name] += 1
    end
  end

  def reflection_includes
    WorkPackage.reflections.keys.map(&:to_sym) & all_includes.map(&:to_sym)
  end

  def reflection_alias(reflection, count)
    if count.zero?
      reflection.klass.table_name
    else
      reflection.alias_candidate(WorkPackage.table_name)
    end
  end

  def all_filter_includes(query)
    query.filters.map(&:includes)
  end

  def all_filter_joins
    query.filters.map(&:joins).flatten.compact
  end

  def filter_merges
    query.filters.inject(::WorkPackage.unscoped) do |scope, filter|
      scope = scope.merge(filter.scope)
      scope
    end
  end

  def clean_symbol_list(list)
    list.flatten.compact.uniq.map(&:to_sym)
  end
end
