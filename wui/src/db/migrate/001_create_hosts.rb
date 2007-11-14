class CreateHosts < ActiveRecord::Migration
  def self.up
    create_table :hosts do |t|
      t.column :uuid,        :string
      t.column :num_cpus,    :integer
      t.column :cpu_speed,   :integer
      t.column :arch,        :string
      t.column :memory,      :integer
    end
  end

  def self.down
    drop_table :hosts
  end
end