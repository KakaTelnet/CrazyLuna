#!/usr/bin/env ruby
# Validate this portable Skill package with Ruby's standard library.
# This is a static package check, not a host loader or model execution test.
require 'yaml'
require 'pathname'

module LunaStrategistValidation
  class Invalid < StandardError; end

  def self.check(condition, message)
    raise Invalid, message unless condition
  end

  def self.mapping(text, label)
    value = YAML.safe_load(text)
    check(value.is_a?(Hash), "#{label}: expected a YAML mapping")
    value
  rescue Psych::Exception => e
    raise Invalid, "#{label}: #{e.message}"
  end

  # Accept document contents so configuration variants can be checked without writes.
  def self.validate(documents)
    skill = documents.fetch('SKILL.md')
    ui = mapping(documents.fetch('agents/openai.yaml'), 'UI')
    models = documents.fetch('references/models.md')
    front_match = skill.match(/\A---\n(.*?)\n---(?:\n|\z)/m)
    check(front_match, 'SKILL.md: missing YAML frontmatter')
    front = mapping(front_match[1], 'frontmatter')
    fields = %w[name description license allowed-tools metadata disable-model-invocation]
    check((front.keys - fields).empty?, 'frontmatter: unsupported field')
    check(front['name'] == 'luna-strategist', 'frontmatter: name must be luna-strategist')
    description = front['description']
    check(description.is_a?(String) && !description.strip.empty? && description.length <= 1024 &&
          !description.match?(/[<>]/), 'frontmatter: invalid description')
    check(front['disable-model-invocation'] == true, 'Claude Code: manual invocation policy required')
    check(ui['policy'].is_a?(Hash) && ui['policy']['allow_implicit_invocation'] == false,
          'Codex: manual invocation policy required')
    interface = ui['interface']
    check(interface.is_a?(Hash), 'UI: interface mapping required')
    check(interface['display_name'].is_a?(String) && !interface['display_name'].strip.empty?,
          'UI: display_name required')
    short = interface['short_description']
    check(short.is_a?(String) && (25..64).cover?(short.length), 'UI: short_description must have 25-64 characters')
    prompt = interface['default_prompt']
    check(prompt.is_a?(String) && prompt.include?('$luna-strategist'), 'UI: default_prompt must name $luna-strategist')

    configs = models.scan(/^```yaml\n(.*?)\n```\s*$/m)
    check(configs.length == 1, 'models: expected one editable YAML configuration')
    config = mapping(configs.first.first, 'models')
    check((config.keys - %w[roles alternative_models]).empty?, 'models: unsupported configuration field')
    roles = config['roles']
    check(roles.is_a?(Hash) && roles.keys.sort == %w[coordinator strategist verifier worker],
          'models: roles must contain strategist, coordinator, worker and verifier only')
    roles.each do |role, settings|
      label = "models: #{role}"
      check(settings.is_a?(Hash) && settings.keys.sort == %w[model reasoning_preference],
            "#{label}: model and reasoning_preference required, no extra fields")
      model = settings['model']
      check(model.is_a?(String) && model.match?(/\A\S+\z/) && model != 'auto',
            "#{label}: model must be an explicit nonempty ID")
      check(%w[medium high].include?(settings['reasoning_preference']),
            "#{label}: reasoning_preference must be medium or high")
    end
    alternatives = config['alternative_models']
    check(alternatives.is_a?(Array) && alternatives.uniq == alternatives &&
          alternatives.all? { |id| id.is_a?(String) && id.match?(/\A\S+\z/) && id != 'auto' },
          'models: alternative_models must be an array of unique explicit IDs')

    documents.each do |path, text|
      next unless path.end_with?('.md')
      fence = nil
      text.each_line do |line|
        check(!line.match?(/[ \t]+\r?\n\z/), "#{path}: trailing whitespace")
        marker = line.match(/^\s*(`{3,}|~{3,})(.*)$/)
        if marker
          if fence.nil?
            fence = marker[1]
          elsif marker[1][0] == fence[0] && marker[1].length >= fence.length && marker[2].strip.empty?
            fence = nil
          end
          next
        end
        next if fence
        check(!line.match?(/^\s*\[TODO:/), "#{path}: unfinished scaffold")
        line.scan(/\]\(([^)]+)\)/).flatten.each do |link|
          next if link.match?(/\A(?:https?:|#)/)
          relative = link.split('#', 2).first
          target = Pathname.new(File.join(File.dirname(path), relative)).cleanpath.to_s
          check(!Pathname.new(relative).absolute? && !target.start_with?('../') && documents.key?(target),
                "#{path}: missing or external package resource #{link}")
        end
      end
      check(fence.nil?, "#{path}: unclosed code fence")
    end
    true
  rescue KeyError => e
    raise Invalid, "Missing package resource: #{e.key}"
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    raise LunaStrategistValidation::Invalid, 'Usage: ruby validate.rb [skill-directory]' if ARGV.length > 1
    root = ARGV.empty? ? File.expand_path('..', __dir__) : File.expand_path(ARGV.first)
    documents = Dir.glob(File.join(root, '**', '*')).select { |path| File.file?(path) }.to_h do |path|
      [path.delete_prefix(root + '/'), File.read(path)]
    end
    LunaStrategistValidation.validate(documents)
    puts 'PASS: luna-strategist portable package profile (static only)'
    puts 'Host loading, model availability and task execution are not verified by this check.'
  rescue LunaStrategistValidation::Invalid, SystemCallError => e
    warn "FAIL: #{e.message}"
    exit 1
  end
end
