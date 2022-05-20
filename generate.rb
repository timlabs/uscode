=begin

TO DO:

WILL NOT DO:
- table of contents
- report that statutory-body-6em is missing from usc.css?
- bigger headings (h1 and h2)
- unicode roman numerals - still there will be out-of-orders.
- capitalization of paths - some are upper, some lower, but this comes from expcite
- move order name stuff to process_tree (don't think this will work, need order names in paths)
- move remove_bracketed to process_tree (but it needs to precede order name stuff)

naming options: [all = 3727]
  1. do nothing [bad = 278]
  2. put 0s in front of top-level Titles, ignore everything else [bad = 278]
  3. put 0s in front of numerical names, ignore everything else [bad = 249]
  4. put 0s in front of numerical names, use unicode for roman numerals, ignore everything else
  5. put 0s in front of top-level Titles, put section numbers for everything which has them, ignore rest
  6. put 0s in front of top-level Titles, put section numbers for everything which has them, ascending numbers for rest
  7. put USC sortcodes in front of all names [but these are consecutive per Title - what if a new path is inserted?]

# tested: GitHub preview max is 512,000 bytes
# expcite tree has 58,132 leaves
# biggest leaf is 346,703 bytes (.md)
# there is a node whose children are all leaves which is 1,473,970 bytes (.md)
# with leaves as files, file count is 67,288
# using GitHub preview max as limit, file count is 3,973

=end

require 'fileutils'
require 'ox'
require 'reverse_markdown'

Ox.default_options = {
  encoding: 'UTF-8',
  skip: :skip_off,
}

def init_command_line_args
  if ARGV.size != 2
    puts "usage: ruby #{$PROGRAM_NAME} [input folder] [output folder]"
    exit
  end

  $input_folder, $output_folder = ARGV.collect {|path| File.expand_path path}

  if not File.exist? $input_folder
    puts 'error: input folder does not exist'
    exit
  end
  if File.exist? $output_folder
    puts 'error: output folder already exists'
    exit
  end
  if not File.exist? File.dirname $output_folder
    puts 'error: parent of output folder does not exist'
    exit
  end
end

def init_globals
  $heads = [
    'usc-title-head', 'title-head', 'subtitle-head', 'large-item-head',
    'reorganizationplan-head', 'chapter-head', 'item-head', 'subchapter-head',
    'part-head', 'subpart-head', 'division-head', 'subdivision-head',
    'reorganizationplan-subhead', 'section-head', 'note-head',
    'subsection-head', 'analysis-subhead', 'form-head'
  ]

  indent_map_inverted = {
    0 => ['statutory-body-block-1em', 'statutory-body', 'statutory-body-block',
          'statutory-body-flush2_hang4', 'tableftnt', 'paragraph-head',
          'note-body',
          # these are actually -1
          'statutory-body-flush0_hang2', 'note-body-flush0_hang1',
          'note-body-block', 'note-sub-head'],
    1 => ['statutory-body-1em', 'statutory-body-flush2_hang3',
          'statutory-body-block-2em', 'subparagraph-head', 'note-body-1em',
          'note-body-flush0_hang2', 'note-body-flush1_hang2'],
    2 => ['statutory-body-2em', 'clause-head', 'note-body-2em', 'note-body-flush3_hang4'],
    3 => ['statutory-body-3em', 'statutory-body-block-4em', 'subclause-head',
          'note-body-3em'],
    4 => ['statutory-body-4em', 'subsubclause-head', 'usc28aForm-left', 'usc28aform-right'],
    5 => ['statutory-body-5em'],
    6 => ['statutory-body-6em'],
  }
  $indents = {}
  indent_map_inverted.each {|i, names|
    names.each {|name| $indents[name] = i}
  }

  $skips = ['notes', 'analysis', 'sourcecredit', 'titleenactmentcredit',
            'appendix-effectivedate']
end

def clean_up! e, in_small_caps = false
  if e.name == 'div' and e['class'] == 'dispo'
    # extract table from div
    raise unless e.nodes[1].name == 'table'
    e.name = e.nodes[1].name
    e.attributes.replace e.nodes[1].attributes
    e.nodes.replace e.nodes[1].nodes
  end
  in_small_caps = true if e.name == 'cap-smallcap'
  in_small_caps = true if e['class'] == 'presidential-signature' # per usc.css
  (e.nodes.size-1).downto(0) {|i|
    child = e.nodes[i]
    case child
      when Ox::Element
        clean_up! child, in_small_caps
        if child.name == 'sup'
          # remove non-breaking space before superscript
          if i > 0 and e.nodes[i-1].is_a? String and e.nodes[i-1].end_with? "\u00a0"
            e.nodes[i-1].chop!
          end
          # remove footnotes that are just links (only used for "So in original")
          if child.nodes.size == 1 and child.nodes[0].is_a? Ox::Element and child.nodes[0].name == 'a'
            e.nodes.delete_at i
          end
        elsif child.name == 'tr' and child['class'] == 'tablerule'
          # remove table rules (not rendered by GitHub)
          e.nodes.delete_at i
        elsif child.name == 'p' and child['class'] == 'intabledata'
          # replace line breaks in tables with spaces
          e.nodes[i..i] = [' '] + child.nodes
        elsif child.name == 'cap-smallcap'
          # "bring up" grandchild nodes which have been capitalized
          e.nodes[i..i] = child.nodes 
        elsif child.name == 'caption'
          # remove caption tags (not rendered by GitHub)
          if child.nodes.size == 1 and child.nodes[0] == "\u00a0"
            e.nodes.delete_at i # remove empty caption
          else
            e.nodes[i..i] = child.nodes
          end
        end
      when String
        e.nodes[i] = child.upcase if in_small_caps
    end
  }
  nil
end

def element_to_s e
  raise unless e.is_a? Ox::Element
  Ox.dump e, indent: -1
end

def process_flat nodes
  indent = -1
  skip = nil
  content = StringIO.new

  nodes.each {|node|

    if node.is_a? Ox::Comment
      if not skip and node.value.start_with? 'field-start'
        field = node.value[12..-1]
        return '' if field == 'repealedhead' # repealed, so stop here
        return '' if field == 'omittedhead' # omitted, so stop here
        skip = field if $skips.include? field
      elsif skip and node.value.start_with? 'field-end'
        field = node.value[10..-1]
        skip = nil if field == skip
      end
      next
    end
    next if skip

    next if node.class == String and node.strip.empty?
    next if node.class == String and node.strip == '*demo*' # Title 20
    next if node.class == String and node.strip == 'T' # 116-344 Title 14

    binding.irb unless node.class == Ox::Element
    raise node.class.to_s unless node.class == Ox::Element
    e = node
    clean_up! e
    e_str = element_to_s e
    markdown = ReverseMarkdown.convert e_str

    if e['class'] == 'analysis-style-table'
      # only occurs in Title 46
      rows = e.nodes.reject {|node| node.class == String and node.strip.empty?}
      max = rows.collect {|row| row.nodes.size}.max
      content.puts "| | #{"&nbsp;" * 10} " * max
      content.puts (['-'] * max * 2).join '|'
      rows.each {|row|
        items = row.nodes.collect {|row_e|
          ReverseMarkdown.convert(element_to_s row_e).strip
        }
        content.puts items.collect {|item| "| #{item} | "}.join
      }

    elsif e['class'] == 'item-head' and e.nodes[0].is_a? String and e.nodes[0].start_with? '"ARTICLE'
      # in part of Title 18a, "item" should be centered
      raise unless e.nodes.size == 1
      content.puts "<p align='center'>#{e.nodes[0]}</p>\n\n"

    elsif e['class'] == 'formula'
      raise unless e_str.start_with? '<h3 class="formula">' and e_str.end_with? '</h3>'
      # markdown is not rendered between html tags, so don't convert
      content.puts "<p align='center'>#{e_str[20...-5]}</p>\n\n"

    elsif ['source-credit', 'footnote', 'rules-form-source-credit'].include? e['class'] 
      # skip notes and analysis
    
    elsif ['Q04', 'Q08'].include? e['class'] # <br>
      content.puts

    elsif e.name == 'p' and (e['class'] == '5800I01' or not e['class'])
      raise unless markdown.delete("&nbsp;").strip.empty? # empty <p>
      content.puts

    elsif e.name == 'table'
      # if there is a caption, add a newline before the first row
      bar = markdown.index '|'
      markdown.insert bar, "\n\n" if bar > 0
      # indent tables (and stop them from breaking lists)
      markdown = markdown.lines.map {|line| '  ' * (indent+1) + line}.join
      content.puts markdown
    
    elsif e.name == 'img'
      # note: uscode.house.gov images are broken because they do not include "Content-Type"
      markdown = '  ' * (indent+1) + markdown.strip
      content.puts markdown

    elsif $heads.include? e['class']
      if markdown.include?('. Transferred') or markdown.include?('. Repealed')
        return '' if content.string.empty? # main head, so stop here
      end
      content.puts markdown

    elsif $indents.keys.include? e['class']
      i = $indents[e['class']]
      if i > indent+2
        # will not work with spaces, so use asterisks
        markdown = '* ' * (i+1) + markdown
      else
        markdown = '  ' * i + '* ' + markdown
      end
      content.puts markdown
      indent = i
        
    elsif ['signature', 'note-body-small', 'presidential-signature'].include? e['class']
      content.puts markdown
        
    else
      raise "unexpected element #{e_str}"

    end
  }
  content.string.strip
end

def name_only? content, raw_name
  # check whether the content only contains the name
  name_to_compare = raw_name.gsub('—', '-').downcase
  subs = {'—' => '-', '/' => "\u2215", '&nbsp;' => ' ', '**' => ''}
  content_to_compare = subs.inject(content.downcase) {|s,(k,v)| s.gsub k, v}
  return true if content_to_compare =~ /\A#+ (\*\*)?#{Regexp.quote name_to_compare}(\*\*)?\z/
  false
end

def save_content content, path, flags
  # skip if there is no content
  return if content.empty?

  path = [$output_folder] + path
  path += ['[PREFACE]'] if flags.include? :preface

  if flags.include? :folder
    path += [path[-1]] # put the file in a folder with the same name
  end

  # create the parent folder(s) if necessary
  FileUtils.mkdir_p File.join path[0...-1] if path.size > 1

  # write any content to path + '.md'
  path = File.join path
  # puts "writing #{content.size} chars to #{path}.md"
  File.write "#{path}.md", content

  $max = 0 if not $max
  $max = [content.size, $max].max
  $counts = [] if not $counts
  $counts << content.size unless content.size == 0
end

def process_tree tree, path = []
  # process the tree recursively and save the resulting markdown contents to
  # disk, using filenames based on the paths.  leaves are merged.

  path += [tree[:name]]
  content = process_flat tree[:preface]
  results = tree[:children].collect {|child| process_tree child, path}

  if results.all? {|status, text| status == :free}
    # they are free for merging, so try to merge them
    texts = [content] + results.collect {|status, text| text}
    result = texts.reject(&:empty?).join "\n\n"
    if result.size <= 512000
      raise if path.size == 1 # at the top, so would have to save
      binding.irb if content.empty? and not results.all? {|status, text| text.empty?}
      return [:merged, result] unless results.all? {|status, text| text.empty?}
      return [:free, ''] if name_only? content, tree[:raw_name]
      return [:free, content]
    end
  end

  # they could not be merged, so save them separately

  content = '' if name_only? content, tree[:raw_name]
  flags = []
  # if some result is a folder, they all have to be folders
  flags << :folder if results.any? {|status, text| status == :folder}

  save_content content, path, flags+[:preface]
  saved = (content.empty? ? [] : ['[PREFACE]'])
  results.each_with_index {|(status, text), i|
    next if status == :folder
    save_content text, path + [tree[:children][i][:name]], flags
    saved << tree[:children][i][:name] unless text.empty?
  }

  $bad = 0 if not $bad
  $bad += 1 if saved != saved.sort
  $all = 0 if not $all
  $all += 1
  $all += saved.size if flags.include? :folder

  [:folder, nil]
end

def remove_bracketed! tree
  raise if tree[:name].start_with? '['  # cannot remove top
  (tree[:children].size-1).downto(0) {|i|
    if tree[:children][i][:name].start_with? '['
      tree[:children].delete_at i
    else
      remove_bracketed! tree[:children][i]
    end
  }
end

def add_raw_names! tree
  tree[:raw_name] = tree[:name]
  tree[:children].each {|child| add_raw_names! child}
end

def fix_order! trees
  # look for a common prefix followed by a number, and pad it with 0s
  /\A(?<prefix>\S* )/ =~ trees[0][:name]
  return false if not prefix
  max = 0
  trees.each {|tree|
    match = tree[:name].match /\A#{Regexp.quote prefix}(?<num>\d+)/
    return false if not match
    max = [match[:num].length, max].max
  }
  trees.each {|tree|
    match = tree[:name].match /\A#{Regexp.quote prefix}(?<num>\d+)(?<rest>.*)/
    tree[:name] = prefix + match[:num].rjust(max, '0') + match[:rest]
  }
  true
end

def add_order_names! tree, top = true
  # make names that will work with GitHub ordering

  # handle the tree itself if it is the top, otherwise it was already handled
  if top
    raise unless /\ATITLE (?<num>\d+)(?<rest>.*)/ =~ tree[:name]
    num = num.rjust 2, '0'
    num << 'a' if rest.include? 'APPENDIX'
    tree[:name] = "TITLE #{num}#{rest}"
  end

  if tree[:children] != tree[:children].sort_by {|child| child[:name]}
    # try to fix the order
    tried = fix_order! tree[:children]
    # fixed = (tree[:children] == tree[:children].sort_by {|child| child[:name]})
    # tree[:children].each {|child| puts child[:name]}
    # puts "tried = #{tried}, fixed = #{fixed}"
  end

  # finally, add names recursively
  tree[:children].each {|child| add_order_names! child, false}
end

def path_from_node node
  return nil unless node.is_a? Ox::Comment
  return nil unless node.value.start_with? 'expcite:'
  path = ReverseMarkdown.convert(node.value[8..-1]).split '!@!'
  path.each {|part| part.gsub! '/', "\u2215"} # visually identical slash
  path.each {|part| part.gsub! 'dash', "\u2013"} # en dash
  path.collect! {|part| part.gsub('&nbsp;', ' ').strip}
  path[-1] = 'APPENDIX' if path[-1].empty? # Titles 11a and 28a
  path
end

def tree_from_nodes nodes, position, path_so_far = []
  node = nodes[position]
  path = path_from_node node
  raise unless path # expect to be called at a path
  raise unless path[0...-1] == path_so_far # the path so far should match
  tree = {:name => path[-1], :preface => [], :children => []}
  position += 1
  while position < nodes.size
    next_path = path_from_node nodes[position]
    if next_path
      break unless next_path.size > path.size
      child, position = tree_from_nodes nodes, position, path
      tree[:children] << child
    else
      tree[:preface] << nodes[position]
      position += 1
    end
  end
  [tree, position]
end

def process_file filename
  puts "loading #{File.basename filename}"
  input = File.read filename

  # fix some invalid characters (encoding unknown)
  # can find these with: grep -axv '.*' *
  input.force_encoding 'binary'
  input.gsub! "o\xFFAE1".b, 'ó'.b
  input.gsub! "a\xFFAE2".b, 'á'.b
  input.gsub! "i\xFFAE4".b, 'ï'.b
  input.force_encoding 'utf-8'

  puts 'making new document'
  document = Ox.parse input
  
  html = document.root
  raise unless html.name == 'html'
  body = html.locate('body').first
  raise unless body.nodes.size == 2
  raise unless body.nodes[0].strip.empty?
  raise unless body.nodes[1].name == 'div' # a single div
  nodes = body.nodes[1].nodes

  start = nodes.index {|node|
    raise unless node.is_a? Ox::Comment or node.strip.empty?
    next false unless (path = path_from_node node)
    raise unless path.size == 1 and path[0].start_with? 'TITLE'
    return if path[0].end_with? '[ELIMINATED]' # skip Title 50a
    true
  }
  
  tree, _ = tree_from_nodes nodes, start
  
  remove_bracketed! tree
  add_raw_names! tree
  add_order_names! tree

  process_tree tree
end

init_command_line_args
init_globals

filenames = [
  # 'PRELIMusc01.htm',
  # 'PRELIMusc02.htm',
  # 'PRELIMusc05.htm',
  # 'PRELIMusc05a.htm',
  # 'PRELIMusc06.htm',
  # 'PRELIMusc07.htm',
  # 'PRELIMusc08.htm',
  # 'PRELIMusc09.htm',
  # 'PRELIMusc10.htm',
  # 'PRELIMusc11.htm',
  # 'PRELIMusc11a.htm',
  # 'PRELIMusc14.htm',
  # 'PRELIMusc15.htm',
  # 'PRELIMusc16.htm',
  # 'PRELIMusc17.htm',
  # 'PRELIMusc18.htm',
  # 'PRELIMusc18a.htm',
  # 'PRELIMusc19.htm',
  # 'PRELIMusc20.htm',
  # 'PRELIMusc22.htm',
  # 'PRELIMusc25.htm',
  # 'PRELIMusc26.htm',
  # 'PRELIMusc28.htm',
  # 'PRELIMusc28a.htm',
  # 'PRELIMusc29.htm',
  # 'PRELIMusc30.htm',
  # 'PRELIMusc33.htm',
  # 'PRELIMusc34.htm',
  # 'PRELIMusc35.htm',
  # 'PRELIMusc36.htm',
  # 'PRELIMusc42.htm',
  # 'PRELIMusc45.htm',
  # 'PRELIMusc46.htm',
  # 'PRELIMusc48.htm',
  # 'PRELIMusc50.htm',
  # 'PRELIMusc54.htm',
]

# filenames.collect! {|filename| File.join $input_folder, filename}

filenames = Dir[File.join $input_folder, '*'].sort

# i = filenames.index File.join $input_folder, 'PRELIMusc47.htm'
# filenames = filenames[i..-1]

filenames.each {|filename| process_file filename}

puts
puts "output file statistics:\n\n"
puts "max file size was #{$max}"
puts "median file size was #{$counts.sort[$counts.size/2]}"
puts "file count was #{$counts.size}"
puts "total file size was #{$counts.inject :+}"
puts "folders = #{$all}"
puts "out of order = #{$bad}"