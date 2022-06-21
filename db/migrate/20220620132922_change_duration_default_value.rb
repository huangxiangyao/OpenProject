class ChangeDurationDefaultValue < ActiveRecord::Migration[7.0]
  def up
    reset_duration(:work_packages)
    reset_duration(:work_package_journals)
  end

  private

  def reset_duration(table)
    execute <<~SQL.squish
      UPDATE #{table} SET duration = NULL
    SQL
  end
end
