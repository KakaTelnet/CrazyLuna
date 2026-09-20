#!/usr/bin/env ruby
# Run the CrazyLuna package validator against the historical configuration and
# package-format regression cases. All mutations stay in memory.
require 'yaml'

require_relative 'validate'

PACKAGE_ROOT = File.expand_path('..', __dir__)

def package_documents
  Dir.glob(File.join(PACKAGE_ROOT, '**', '*')).select { |path| File.file?(path) }.each_with_object({}) do |path, documents|
    relative = path.delete_prefix(PACKAGE_ROOT + '/')
    documents[relative] = File.read(path).dup
  end
end

def replace_frontmatter(documents)
  skill = documents.fetch('SKILL.md')
  match = skill.match(/\A---\n(.*?)\n---(?:\n|\z)/m)
  raise 'SKILL.md frontmatter was not found' unless match

  frontmatter = YAML.safe_load(match[1])
  raise 'SKILL.md frontmatter is not a mapping' unless frontmatter.is_a?(Hash)

  updated = yield(frontmatter)
  raise 'SKILL.md frontmatter mutation did not return a mapping' unless updated.is_a?(Hash)

  yaml = YAML.dump(updated).sub(/\A---\s*\n/, '')
  documents['SKILL.md'] = skill.sub(match[0], "---\n#{yaml}---\n")
end

def replace_model_config(documents)
  models = documents.fetch('references/models.md')
  match = models.match(/^```yaml\n(.*?)\n```\s*$/m)
  raise 'references/models.md YAML configuration was not found' unless match

  config = YAML.safe_load(match[1])
  raise 'models configuration is not a mapping' unless config.is_a?(Hash)

  updated = yield(config)
  raise 'models mutation did not return a mapping' unless updated.is_a?(Hash)

  yaml = YAML.dump(updated).sub(/\A---\s*\n/, '').sub(/\n\z/, '')
  documents['references/models.md'] = models.sub(match[0], "```yaml\n#{yaml}\n```\n")
end

def replace_ui_config(documents)
  path = 'agents/openai.yaml'
  ui = YAML.safe_load(documents.fetch(path))
  raise 'UI configuration is not a mapping' unless ui.is_a?(Hash)

  updated = yield(ui)
  raise 'UI mutation did not return a mapping' unless updated.is_a?(Hash)

  documents[path] = YAML.dump(updated)
end

def independent_documents(base)
  base.each_with_object({}) { |(path, content), copy| copy[path.dup] = content.dup }
end

base = package_documents
cases = [
  ['C01', 'current package accepted', :accept, ->(documents) { documents }],
  ['C02', 'reasoning_preference=high accepted', :accept, lambda { |documents|
    replace_model_config(documents) { |config| config.merge('reasoning_preference' => 'high') }
    documents
  }],
  ['C03', 'reasoning_preference omitted accepted', :accept, lambda { |documents|
    replace_model_config(documents) { |config| config.reject { |key, _| key == 'reasoning_preference' } }
    documents
  }],
  ['C04', 'reasoning_preference=null rejected', :reject, lambda { |documents|
    replace_model_config(documents) { |config| config.merge('reasoning_preference' => nil) }
    documents
  }],
  ['C05', 'reasoning_preference empty string rejected', :reject, lambda { |documents|
    replace_model_config(documents) { |config| config.merge('reasoning_preference' => '') }
    documents
  }],
  ['C06', 'reasoning_preference array rejected', :reject, lambda { |documents|
    replace_model_config(documents) { |config| config.merge('reasoning_preference' => ['high']) }
    documents
  }],
  ['C07', 'reasoning_preference=custom-effort accepted', :accept, lambda { |documents|
    replace_model_config(documents) { |config| config.merge('reasoning_preference' => 'custom-effort') }
    documents
  }],
  ['C08', 'allowed_models empty rejected', :reject, lambda { |documents|
    replace_model_config(documents) { |config| config.merge('allowed_models' => []) }
    documents
  }],
  ['C09', 'fixed default outside allowed_models rejected', :reject, lambda { |documents|
    replace_model_config(documents) do |config|
      allowed = config.fetch('allowed_models')
      outside = '__crazy_luna_model_not_in_allowed_models__'
      raise 'C09 mutation candidate unexpectedly allowed' if allowed.include?(outside)
      config.merge('default_model' => outside)
    end
    documents
  }],
  ['C10', 'unsupported reasoning_pref rejected', :reject, lambda { |documents|
    replace_model_config(documents) { |config| config.merge('reasoning_pref' => 'high') }
    documents
  }],
  ['C11', 'Claude Code manual invocation policy required', :reject, lambda { |documents|
    replace_frontmatter(documents) { |frontmatter| frontmatter.reject { |key, _| key == 'disable-model-invocation' } }
    documents
  }],
  ['C12', 'Codex manual invocation policy required', :reject, lambda { |documents|
    replace_ui_config(documents) do |ui|
      policy = ui.fetch('policy').merge('allow_implicit_invocation' => true)
      ui.merge('policy' => policy)
    end
    documents
  }],
  ['C13', 'malformed UI YAML rejected', :reject, lambda { |documents|
    documents['agents/openai.yaml'] = "interface: [\n"
    documents
  }],
  ['C14', 'missing Skill reference rejected', :reject, lambda { |documents|
    skill = documents.fetch('SKILL.md')
    changed = skill.sub('](references/models.md)', '](references/missing.md)')
    raise 'C14 reference link was not found' if changed == skill
    documents['SKILL.md'] = changed
    documents
  }],
  ['C15', 'missing reference script rejected', :reject, lambda { |documents|
    documents['references/models.md'] = documents.fetch('references/models.md') + "\n- [broken](scripts/missing.rb)\n"
    documents
  }],
  ['C16', 'unclosed Skill code fence rejected', :reject, lambda { |documents|
    documents['SKILL.md'] = documents.fetch('SKILL.md') + "\n```ruby\nputs 'unclosed'\n"
    documents
  }]
]

passed = 0
results = []
cases.each do |id, name, expectation, builder|
  begin
    documents = independent_documents(base)
    built = builder.call(documents)
    raise 'case builder did not return a document Hash' unless built.is_a?(Hash)

    if expectation == :accept
      result = CrazyLunaValidation.validate(built)
      raise "expected true, got #{result.inspect}" unless result == true
    else
      begin
        result = CrazyLunaValidation.validate(built)
        raise "expected CrazyLunaValidation::Invalid, got #{result.inspect}"
      rescue CrazyLunaValidation::Invalid => error
        expected_fragments = {
          'C04' => 'models: reasoning_preference',
          'C05' => 'models: reasoning_preference',
          'C06' => 'models: reasoning_preference',
          'C08' => 'models: allowed_models',
          'C09' => 'models: fixed default',
          'C10' => 'models: unsupported configuration field',
          'C11' => 'Claude Code: manual invocation policy required',
          'C12' => 'Codex: manual invocation policy required',
          'C13' => 'UI:',
          'C14' => 'SKILL.md: missing or external package resource',
          'C15' => 'references/models.md: missing or external package resource',
          'C16' => 'SKILL.md: unclosed code fence'
        }
        fragment = expected_fragments.fetch(id)
        raise "unexpected rejection: #{error.message}" unless error.message.include?(fragment)
      end
    end

    passed += 1
    results << [id, name, 'PASS']
  rescue StandardError => error
    results << [id, name, 'FAIL', "#{error.class}: #{error.message}"]
  end
end

results.each do |id, name, status, detail|
  line = "#{id} #{name}: #{status}"
  line += " (#{detail})" if detail
  puts line
end
failed = results.length - passed
puts "TOTAL: #{results.length} | PASS: #{passed} | FAIL: #{failed}"
exit(failed.zero? ? 0 : 1)
