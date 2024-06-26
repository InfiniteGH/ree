# frozen_string_literal: true

RSpec.describe Ree::ObjectDsl do
  before :all do
    Ree.enable_irb_mode
  end

  after :all do
    Ree.disable_irb_mode
  end

  module ObjectDslPackage
  end

  it 'does not allow to use dsl for anonymous classes' do
    expect {
      module ObjectDslPackage
        Class.new do
          include Ree::FnDSL

          fn :anonymous_class_fn
        end
      end
    }.to raise_error(Ree::Error) do |e|
      expect(e.message).to eq("Anonymous classes are not supported")
    end
  end

  it 'does not allow top level objects' do
    expect {
      class ObjectDslPackageTopLevelClass
        include Ree::FnDSL

        fn :top_level_class_fn
      end
    }.to raise_error(Ree::Error) do |e|
      expect(e.message).to eq("Object declarations should only appear for classes declared inside modules")
    end
  end

  it 'it does not allow to use dsl for deeply nested submodules' do
    expect {
      module ObjectDslPackage
        module Level2
          module Level3
            class DeeplyNestedClass
              include Ree::FnDSL

              fn :deeply_nested_class
            end
          end
        end
      end
    }.to raise_error(Ree::Error) do |e|
      expect(e.message).to eq("Objects should be declared inside parent modules or inside there submodules")
    end
  end

  it 'checks object name & corresponding class name' do
    expect {
      class ObjectDslPackage::ObjectClass
        include Ree::FnDSL

        fn :object
      end
    }.to raise_error(Ree::Error) do |e|
      expect(e.message).to eq(":object does not correspond to class name ObjectClass. Change object name to 'object_class' or change name of the class")
    end
  end
end
