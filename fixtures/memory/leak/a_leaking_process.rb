# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2025, by Samuel Williams.

require "json"

module Memory
	module Leak
		ALeakingProcess = Sus::Shared("a leaking process") do
			def write_message(**message)
				@child.puts(JSON.dump(message))
			end
			
			def read_message
				if line = @child.gets
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
			
			around do |&block|
				IO.popen(["ruby", File.expand_path("leaking_child.rb", __dir__)], "r+") do |child|
					@child = child
					
					super(&block)
				ensure
					child.close
					@child = nil
				end
			end
		end
	end
end
