class CreateSavedSearchRuns < ActiveRecord::Migration
  def self.up
    create_table :saved_search_runs do |t|
      t.references :saved_search, :null => false, :on_update => :cascade, :on_delete => :cascade
      t.column :run_count, :integer, :null => false, :default => 1
      #FIXME
      t.column :run_time, :integer
      t.timestamps
    end
  end

  def self.down
    drop_table :saved_search_runs
  end
end
