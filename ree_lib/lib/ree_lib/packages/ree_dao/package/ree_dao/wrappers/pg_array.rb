# frozen_string_literal: true

require "sequel/extensions/pg_array"

class ReeDao::PgArray < ReeMapper::AbstractWrapper
  contract(
    Any,
    Kwargs[
      name: String,
      role: Nilor[Symbol, ArrayOf[Symbol]],
      fields_filters: ArrayOf[ReeMapper::FieldsFilter],
      location: Nilor[String],
    ] => Or[Sequel::Postgres::PGArray, String]
  )
  def db_dump(value, name:, role: nil, fields_filters: [], location: nil)
    if !value.is_a?(Array)
      raise ReeMapper::TypeError.new("`#{name}` should be an array, got `#{truncate(value.inspect)}`", location)
    end

    value = value.map.with_index do |el, index|
      subject.type.db_dump(
        el,
        name: "#{name}[#{index}]",
        role: role,
        fields_filters: fields_filters + [subject.fields_filter],
        location: subject.location,
      )
    end

    if value.empty?
      "{}"
    else
      Sequel.pg_array(value)
    end
  end

  contract(
    Any,
    Kwargs[
      name: String,
      role: Nilor[Symbol, ArrayOf[Symbol]],
      fields_filters: ArrayOf[ReeMapper::FieldsFilter],
      location: Nilor[String],
    ] => Array
  ).throws(ReeMapper::TypeError)
  def db_load(value, name:, role: nil, fields_filters: [], location: nil)
    if !value.is_a?(Sequel::Postgres::PGArray)
      raise ReeMapper::TypeError.new("`#{name}` should be a Sequel::Postgres::PGArray, got `#{truncate(value.inspect)}`", location)
    end

    value.map.with_index do |val, index|
      subject.type.db_load(
        val,
        name: "#{name}[#{index}]",
        role: role,
        fields_filters: fields_filters + [subject.fields_filter],
        location: subject.location,
      )
    end
  end
end
