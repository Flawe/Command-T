# Copyright 2010-2011 Wincent Colaiuta. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright notice,
#    this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDERS OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

require 'command-t/vim'
require 'command-t/scanner'

module CommandT
  # Reads the current directory recursively for the paths to all regular files.
  class FileScanner < Scanner
    class FileLimitExceeded < ::RuntimeError; end

    def initialize path = Dir.pwd, options = {}
      @path                 = path
      @max_depth            = options[:max_depth] || 15
      @max_files            = options[:max_files] || 10_000
      @scan_dot_directories = options[:scan_dot_directories] || false
	  @file_types			= options[:file_types] || ''
    end

    def paths
	  return @paths unless @paths.nil?
      if File.exist?($cache_file)
	    File.open($cache_file, "r") do |cache|
		  if (Marshal.load(cache) <=> @path) == 0
			@paths = Marshal.load(cache)
		  end
		end
	  end
	  return @paths unless @paths.nil?
	  begin
        @paths = []
        @depth = 0
        @files = 0
        @prefix_len = @path.chomp('/').length
        add_paths_for_directory @path, @paths
		cache_files @paths
      rescue FileLimitExceeded
      end
      @paths
    end

    def flush
      @paths = nil
	  lama
    end

    def path= str
      if @path != str
        @path = str
        @paths = nil
      end
    end

  private

    def path_excluded? path
      # first strip common prefix (@path) from path to match VIM's behavior
      path = path[(@prefix_len + 1)..-1]
      path = VIM::escape_for_single_quotes path
      ::VIM::evaluate("empty(expand(fnameescape('#{path}')))").to_i == 1
    end
	
	def explicit_file_type? path
	  if (@file_types <=> '') == 0
		return false
	  end
	  @file_types.split(',').each {
		|extension|
		if (File.extname(path) <=> extension) == 0
		  return true
		end
	  }
	  return false
	end

    def add_paths_for_directory dir, accumulator
      Dir.foreach(dir) do |entry|
        next if ['.', '..'].include?(entry)
        path = File.join(dir, entry)
        unless path_excluded?(path)
          if File.file?(path) and explicit_file_type?(path)
            @files += 1
            raise FileLimitExceeded if @files > @max_files
            accumulator << path[@prefix_len + 1..-1]
          elsif File.directory?(path)
            next if @depth >= @max_depth
            next if (entry.match(/\A\./) && !@scan_dot_directories)
            @depth += 1
            add_paths_for_directory path, accumulator
            @depth -= 1
          end
        end
      end
    rescue Errno::EACCES
      # skip over directories for which we don't have access
    end
	
	def cache_files files
	  File.open($cache_file, "w") do |cache|
		Marshal.dump(@path, cache)
		Marshal.dump(@paths, cache)
	  end
	end
  end # class FileScanner
end # module CommandT
