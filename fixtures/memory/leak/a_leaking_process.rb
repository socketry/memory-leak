# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2025, by Samuel Williams.

require "json"

module Memory
	module Leak
		class LeakingChild
			def initialize
				@io = IO.popen(["ruby", File.expand_path("leaking_child.rb", __dir__)], "r+")
			end
			
			def process_id
				@io.pid
			end
			
			def close
				if io = @io
					@io = nil
					io.close
				end
			end
			
			def write_message(**message)
				@io.puts(JSON.dump(message))
			end
			
			def read_message
				if line = @io.gets
					return JSON.parse(line, symbolize_names: true)
				end
			end
			
			def wait_for_message(action)
				while message = read_message
					if message[:action] == action
						return message
					end
				end
			end
		end
		
		ALeakingProcess = Sus::Shared("a leaking process") do
			around do |&block|
				begin
					@child = LeakingChild.new
					
					super(&block)
				ensure
					@child&.close
					@child = nil
				end
			end
		end
	end
end
