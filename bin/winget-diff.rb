#!/usr/bin/env ruby
# usage: winget-diff.rb OLD.winget... (--build HOST | -- NEW.winget...)
#
# Compares two sets of winget configuration documents unit by unit, by id: the resource, the
# directives, the settings and dependsOn, after parsing both as YAML (so quoting, key order and
# which document a unit sits in do not count). Written for decisions/0020's proof that a render
# holds exactly the units of the hand-written files it replaced, and for merging a branch that
# still edits such a file: give it that file (git show <rev>:<path> > old.winget) and the build.
#   --build HOST   the new side is windows/build/HOST/*.winget, in manifest.json's order; a
#                  Script unit that runs windows/units/<id>.ps1 is compared by that file's Get,
#                  Test and Set bodies (dedented, the final newline aside) against the old
#                  side's inline scripts
# A dependsOn the new side drops is accepted only when the unit it names sits in an earlier
# document there (converge.ps1 runs the documents in order); it is printed as a note.
#   -h, --help     this text
#
# exit: 0 no differences · 1 differences (listed) · 2 bad usage or an unreadable file
# needs: ruby with psych (the Mac's Homebrew ruby; on Arch: pacman -S ruby)
# see: bin/render-windows.sh, docs/platforms/windows/renderer.md

require 'json'
require 'yaml'

ROOT = File.expand_path('..', __dir__)
CALL = /\A& \(\[scriptblock\]::Create\(\[IO\.File\]::ReadAllText\('C:\\ProgramData\\dram\\units\\([^']+)\.ps1'\)\)\) -Mode (Get|Test|Set)\z/

def usage(code)
  text = File.readlines(__FILE__).drop(1).take_while { |l| l.start_with?('#') }.map { |l| l.sub(/^# ?/, '') }
  code.zero? ? puts(text) : warn(text.first)
  exit code
end

def units(files)
  out = {}
  files.each_with_index do |f, i|
    doc = YAML.safe_load(File.read(f))
    (doc.dig('properties', 'resources') || []).each do |u|
      raise "#{f}: unit #{u['id']} twice" if out.key?(u['id'])
      out[u['id']] = u.merge('_file' => File.basename(f), '_order' => i)
    end
  end
  out
rescue StandardError => e
  warn "winget-diff: #{e.message}"
  exit 2
end

# a unit file's body for one mode: the lines between "function <Mode>-DramUnit {" and the
# next "}" at column 0, two spaces of indentation off (none inside a here-string)
def body(id, mode)
  path = File.join(ROOT, 'windows', 'units', "#{id}.ps1")
  lines = File.readlines(path, chomp: true)
  start = lines.index("function #{mode}-DramUnit {") or raise "#{path}: no #{mode}-DramUnit"
  stop = (start + 1...lines.size).find { |i| lines[i] == '}' } or raise "#{path}: #{mode}-DramUnit never closes"
  here = false
  lines[start + 1...stop].map do |l|
    if here
      here = false if l.start_with?("'@", '"@')
      l
    else
      here = true if l.end_with?("@'", '@"')
      l.sub(/\A {1,2}/, '')
    end
  end.join("\n")
end

olds = []
news = []
build = nil
side = olds
args = ARGV.dup
until args.empty?
  a = args.shift
  case a
  when '-h', '--help' then usage(0)
  when '--build' then build = args.shift or usage(2)
  when '--' then side = news
  when /\A-/ then usage(2)
  else side << a
  end
end
usage(2) if olds.empty? || (build.nil? == news.empty?)
if build
  dir = File.join(ROOT, 'windows', 'build', build)
  manifest = JSON.parse(File.read(File.join(dir, 'manifest.json')))
  news = manifest['documents'].map { |d| File.join(dir, d['file']) }
end

old = units(olds)
new = units(news)
resolved = {} # "id/GetScript" => true for each block read from a unit file
new.each_value do |u|
  next unless u['resource'] == 'PSDscResources/Script'
  (u['settings'] || {}).each do |k, v|
    m = CALL.match(v.to_s) or next
    raise "#{u['id']}: #{k} calls #{m[1]}.ps1" unless m[1] == u['id']
    raise "#{u['id']}: #{k} calls -Mode #{m[2]}" unless k == "#{m[2]}Script"
    u['settings'][k] = body(m[1], m[2])
    resolved["#{u['id']}/#{k}"] = true
  end
rescue StandardError => e
  warn "winget-diff: #{e.message}"
  exit 2
end

diffs = []
notes = []
(old.keys - new.keys).sort.each { |id| diffs << "only in the old: #{id} (#{old[id]['_file']})" }
(new.keys - old.keys).sort.each { |id| diffs << "only in the new: #{id} (#{new[id]['_file']})" }
(old.keys & new.keys).sort.each do |id|
  a = old[id]
  b = new[id]
  diffs << "#{id}: resource #{a['resource']} -> #{b['resource']}" if a['resource'] != b['resource']
  diffs << "#{id}: directives #{a['directives'].inspect} -> #{b['directives'].inspect}" if a['directives'] != b['directives']
  sa = a['settings'] || {}
  sb = b['settings'] || {}
  (sa.keys | sb.keys).sort.each do |k|
    x = sa[k]
    y = sb[k]
    next if x == y
    # a function body read from a unit file carries no final newline; an inline block scalar does
    next if resolved["#{id}/#{k}"] && x.is_a?(String) && x.sub(/\n\z/, '') == y
    long = [x, y].any? { |v| v.is_a?(String) && (v.include?("\n") || v.size > 100) }
    diffs << "#{id}: settings.#{k} differs#{long ? " (#{x.to_s.lines.size} -> #{y.to_s.lines.size} lines)" : ": #{x.inspect} -> #{y.inspect}"}"
  end
  da = a['dependsOn'] || []
  db = b['dependsOn'] || []
  (da - db).each do |d|
    if new.key?(d) && new[d]['_order'] < b['_order']
      notes << "#{id}: dependsOn #{d} is kept by document order (#{new[d]['_file']} runs before #{b['_file']})"
    else
      diffs << "#{id}: dependsOn #{d} dropped"
    end
  end
  (db - da).each { |d| diffs << "#{id}: dependsOn #{d} added" }
end

puts "old: #{old.size} units in #{olds.size} document(s); new: #{new.size} units in #{news.size} document(s)" \
     "#{resolved.empty? ? '' : "; #{resolved.size} script block(s) read from windows/units/"}"
olds.each do |f|
  moved = old.values.select { |u| u['_file'] == File.basename(f) }.group_by { |u| new.dig(u['id'], '_file') || '(gone)' }
  puts "  #{File.basename(f)}: " + moved.map { |k, v| "#{v.size} -> #{k}" }.join(', ')
end
notes.each { |n| puts "note: #{n}" }
diffs.each { |d| puts "DIFF #{d}" }
puts "#{diffs.size} difference(s)"
exit(diffs.empty? ? 0 : 1)
