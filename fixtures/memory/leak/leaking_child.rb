# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2025, by Samuel Williams.

require "securerandom"
require "json"

def read_message
	if line = $stdin.gets
		return JSON.parse(line, symbolize_names: true)
	end
end

def write_message(**message)
	$stdout.puts(JSON.dump(message))
	$stdout.flush
end

write_message(action: "ready")

allocations = []
while message = read_message
	case message[:action]
	when "allocate"
		allocations << SecureRandom.hex(message[:size])
		write_message(action: "allocated", size: message[:size])
	when "free"
		allocations.pop
		write_message(action: "freed")
	when "clear"
		allocations.clear
		write_message(action: "cleared")
	when "exit"
		break
	end
end
