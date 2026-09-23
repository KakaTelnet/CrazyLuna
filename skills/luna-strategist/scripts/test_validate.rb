#!/usr/bin/env ruby
# Run the Luna Strategist package validator against role-model configuration and
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

def replace_role_config(documents, role = 'worker')
  replace_model_config(documents) do |config|
    config['roles'][role] = yield(config.fetch('roles').fetch(role))
    config
  end
end

def independent_documents(base)
  base.each_with_object({}) { |(path, content), copy| copy[path.dup] = content.dup }
end

base = package_documents
cases = [
  ['C01', 'current package accepted', :accept, ->(documents) { documents }],
  ['C02', 'worker high with coordinator and verifier unchanged accepted', :accept, lambda { |documents|
    replace_role_config(documents) { |config| config.merge('reasoning_preference' => 'high') }
    documents
  }],
  ['C03', 'worker missing reasoning preference rejected', :reject, lambda { |documents|
    replace_role_config(documents) { |config| config.reject { |key, _| key == 'reasoning_preference' } }
    documents
  }],
  ['C04', 'reasoning_preference=null rejected', :reject, lambda { |documents|
    replace_role_config(documents) { |config| config.merge('reasoning_preference' => nil) }
    documents
  }],
  ['C05', 'reasoning_preference empty string rejected', :reject, lambda { |documents|
    replace_role_config(documents) { |config| config.merge('reasoning_preference' => '') }
    documents
  }],
  ['C06', 'reasoning_preference array rejected', :reject, lambda { |documents|
    replace_role_config(documents) { |config| config.merge('reasoning_preference' => ['high']) }
    documents
  }],
  ['C07', 'unsupported default effort rejected', :reject, lambda { |documents|
    replace_role_config(documents) { |config| config.merge('reasoning_preference' => 'custom-effort') }
    documents
  }],
  ['C08', 'missing coordinator rejected', :reject, lambda { |documents|
    replace_model_config(documents) { |config| config.merge('roles' => config.fetch('roles').reject { |role, _| role == 'coordinator' }) }
    documents
  }],
  ['C09', 'automatic worker model rejected', :reject, lambda { |documents|
    replace_role_config(documents) { |config| config.merge('model' => 'auto') }
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
  }],
  ['C17', 'coordinator high accepted', :accept, lambda { |documents|
    replace_role_config(documents, 'coordinator') { |config| config.merge('reasoning_preference' => 'high') }
    documents
  }],
  ['C18', 'verifier high accepted', :accept, lambda { |documents|
    replace_role_config(documents, 'verifier') { |config| config.merge('reasoning_preference' => 'high') }
    documents
  }],
  ['C19', 'non-mapping role rejected', :reject, lambda { |documents|
    replace_role_config(documents) { |_| 'gpt-5.6-luna' }
    documents
  }],
  ['C20', 'unknown role rejected', :reject, lambda { |documents|
    replace_model_config(documents) { |config| config.merge('roles' => config.fetch('roles').merge('planner' => {})) }
    documents
  }],
  ['C21', 'empty model rejected', :reject, lambda { |documents|
    replace_role_config(documents) { |config| config.merge('model' => '') }
    documents
  }],
  ['C22', 'null alternatives rejected', :reject, lambda { |documents|
    replace_model_config(documents) { |config| config.merge('alternative_models' => nil) }
    documents
  }],
  ['C23', 'empty alternatives accepted', :accept, lambda { |documents|
    replace_model_config(documents) { |config| config.merge('alternative_models' => []) }
    documents
  }],
  ['C24', 'duplicate alternatives rejected', :reject, lambda { |documents|
    replace_model_config(documents) { |config| config.merge('alternative_models' => ['claude-haiku', 'claude-haiku']) }
    documents
  }],
  ['C25', 'legacy global default rejected', :reject, lambda { |documents|
    replace_model_config(documents) { |config| config.merge('default_model' => 'auto') }
    documents
  }],
  ['C26', 'explicit alternative model for worker accepted', :accept, lambda { |documents|
    replace_role_config(documents) { |config| config.merge('model' => 'claude-haiku') }
    documents
  }],
  ['C27', 'unknown role field rejected', :reject, lambda { |documents|
    replace_role_config(documents) { |config| config.merge('reasoning_pref' => 'high') }
    documents
  }],
  ['C28', 'non-mapping roles rejected', :reject, lambda { |documents|
    replace_model_config(documents) { |config| config.merge('roles' => []) }
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
      result = LunaStrategistValidation.validate(built)
      raise "expected true, got #{result.inspect}" unless result == true
    else
      begin
        result = LunaStrategistValidation.validate(built)
        raise "expected LunaStrategistValidation::Invalid, got #{result.inspect}"
      rescue LunaStrategistValidation::Invalid => error
        expected_fragments = {
          'C03' => 'models: worker: model and reasoning_preference required',
          'C04' => 'models: worker: reasoning_preference',
          'C05' => 'models: worker: reasoning_preference',
          'C06' => 'models: worker: reasoning_preference',
          'C07' => 'models: worker: reasoning_preference',
          'C08' => 'models: roles must contain',
          'C09' => 'models: worker: model must be',
          'C10' => 'models: unsupported configuration field',
          'C11' => 'Claude Code: manual invocation policy required',
          'C12' => 'Codex: manual invocation policy required',
          'C13' => 'UI:',
          'C14' => 'SKILL.md: missing or external package resource',
          'C15' => 'references/models.md: missing or external package resource',
          'C16' => 'SKILL.md: unclosed code fence',
          'C19' => 'models: worker: model and reasoning_preference required',
          'C20' => 'models: roles must contain',
          'C21' => 'models: worker: model must be',
          'C22' => 'models: alternative_models',
          'C24' => 'models: alternative_models',
          'C25' => 'models: unsupported configuration field',
          'C27' => 'models: worker: model and reasoning_preference required',
          'C28' => 'models: roles must contain'
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
