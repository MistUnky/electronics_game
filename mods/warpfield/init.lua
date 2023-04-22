warpfield = {}

local S = minetest.get_translator()

local warpfield_trigger_uses = tonumber(minetest.settings:get("warpfield_trigger_uses")) or 0
local warpfield_trigger_cooldown = tonumber(minetest.settings:get("warpfield_cooldown")) or 10

local default_x = {
	octaves = 1,
	scale = "500",
	lacunarity = "2",
	flags = "",
	spread = {
		y = "800",
		x = "800",
		z = "800"
	},
	seed = 33356,
	offset = "1",
	persistence = "0.5"
}

local default_y = {
	octaves = 1,
	scale = "100",
	lacunarity = "2",
	flags = "",
	spread = {
		y = "200",
		x = "200",
		z = "200"
	},
	seed = 33357,
	offset = "1",
	persistence = "0.5"
}

local default_z = {
	octaves = 1,
	scale = "500",
	lacunarity = "2",
	flags = "",
	spread = {
		y = "800",
		x = "800",
		z = "800"
	},
	seed = 33358,
	offset = "1",
	persistence = "0.5"
}

local warpfield_x = minetest.settings:get_np_group("warpfield_x_params") or default_x
local warpfield_y = minetest.settings:get_np_group("warpfield_y_params") or default_y
local warpfield_z = minetest.settings:get_np_group("warpfield_z_params") or default_z

-- For some reason, these numbers are returned as strings by get_np_group.
local tonumberize_params = function(params)
	params.scale = tonumber(params.scale)
	params.lacunarity = tonumber(params.lacunarity)
	params.spread.x = tonumber(params.spread.x)
	params.spread.y = tonumber(params.spread.y)
	params.spread.z = tonumber(params.spread.z)
	params.offset = tonumber(params.offset)
	params.persistence = tonumber(params.persistence)
end
tonumberize_params(warpfield_x)
tonumberize_params(warpfield_y)
tonumberize_params(warpfield_z)

local trigger_stack_size = 99
local trigger_wear_amount = 0
local trigger_tool_capabilities = nil
if warpfield_trigger_uses ~= 0 then
	trigger_stack_size = 1
	trigger_wear_amount = math.ceil(65535 / warpfield_trigger_uses)
	trigger_tool_capabilities = {
        full_punch_interval=1.5,
        max_drop_level=1,
        groupcaps={},
        damage_groups = {},
    }
end

local particle_node_pos_spread = vector.new(0.5,0.5,0.5)
local particle_user_pos_spread = vector.new(0.5,1.5,0.5)
local particle_speed_spread = vector.new(0.1,0.1,0.1)
local min_spark_delay = 30
local max_spark_delay = 120

local trigger_help_addendum = ""
if warpfield_trigger_uses > 0 then
	trigger_help_addendum = S(" This tool can be used @1 times before breaking.", warpfield_trigger_uses)
end

local warp_x
local warp_y
local warp_z

-- An external API to allow use of warp field by other mods
local get_warp_at = function(pos)
	if not warp_x then
		warp_x = minetest.get_perlin(warpfield_x)
		warp_y = minetest.get_perlin(warpfield_y)
		warp_z = minetest.get_perlin(warpfield_z)
	end

	return {x = warp_x:get_3d(pos), y = warp_y:get_3d(pos), z = warp_z:get_3d(pos)}
end
warpfield.get_warp_at = get_warp_at

local player_cooldown = {}

local trigger_def = {
	description = S("Warpfield Trigger"),
	_doc_items_longdesc = S("A triggering device that allows teleportation via warpfield."),
	_doc_items_usagehelp = S("When triggered, this tool and its user will be displaced in accordance with the local warp field's displacement. Simply holding it makes it act as a compass of sorts, showing the current strength of the warp field.") .. trigger_help_addendum,
	inventory_image = "warpfield_spark.png^warpfield_tool_base.png",
	stack_max = trigger_stack_size,
	tool_capabilites = trigger_tool_capabilities,
	sound = {
		breaks = "warpfield_trigger_break",
	},
	on_use = function(itemstack, user, pointed_thing)
	
		local player_name = user:get_player_name()
		if (player_cooldown[player_name] or 0) > 0 then
			return itemstack
		end
	
		local old_pos = user:get_pos()
		local warp = get_warp_at(old_pos)
		local new_pos = vector.add(old_pos, warp)
		
		old_pos.y = old_pos.y + 0.5

		local speed = vector.multiply(vector.direction(old_pos, new_pos), 5/0.5)
		minetest.add_particlespawner({
			amount = 100,
			time = 0.1,
			minpos = vector.subtract(old_pos, particle_node_pos_spread),
			maxpos = vector.add(old_pos, particle_user_pos_spread),
			minvel = vector.subtract(speed, particle_speed_spread),
			maxvel = vector.add(speed, particle_speed_spread),
			minacc = {x=0, y=0, z=0},
			maxacc = {x=0, y=0, z=0},
			minexptime = 0.1,
			maxexptime = 0.5,
			minsize = 1,
			maxsize = 1,
			collisiondetection = false,
			vertical = false,
			texture = "warpfield_spark.png",
		})		
		minetest.sound_play({name="warpfield_teleport_from"}, {pos = old_pos}, true)
	
		user:set_pos({x=new_pos.x, y=new_pos.y-0.5, z=new_pos.z})
		
		new_pos = vector.subtract(new_pos, speed)
		minetest.add_particlespawner({
			amount = 100,
			time = 0.1,
			minpos = vector.subtract(new_pos, particle_node_pos_spread),
			maxpos = vector.add(new_pos, particle_user_pos_spread),
			minvel = vector.subtract(speed, particle_speed_spread),
			maxvel = vector.add(speed, particle_speed_spread),
			minacc = {x=0, y=0, z=0},
			maxacc = {x=0, y=0, z=0},
			minexptime = 0.5,
			maxexptime = 0.5,
			minsize = 1,
			maxsize = 1,
			collisiondetection = false,
			vertical = false,
			texture = "warpfield_spark.png",
		})
		minetest.sound_play({name="warpfield_teleport_to"}, {pos = new_pos}, true)
		
		if trigger_wear_amount > 0 and not minetest.is_creative_enabled(player_name) then
			itemstack:add_wear(trigger_wear_amount)
		end
		player_cooldown[player_name] = warpfield_trigger_cooldown
		
		return itemstack
	end
}

local hud_position = {
	x= tonumber(minetest.settings:get("warpfield_hud_x")) or 0.5,
	y= tonumber(minetest.settings:get("warpfield_hud_y")) or 0.9,
}
local hud_color = tonumber("0x" .. (minetest.settings:get("warpfield_hud_color") or "FFFF00")) or 0xFFFF00
local hud_color_stressed = tonumber("0x" .. (minetest.settings:get("warpfield_hud_color_stressed") or "FF0000")) or 0xFF0000

local player_huds = {}
local function hide_hud(player, player_name)
	local id = player_huds[player_name]
	if id then
		player:hud_remove(id)
		player_huds[player_name] = nil
	end
end
local function update_hud(player, player_name, player_cooldown_val)
	local player_pos = player:get_pos()
	local local_warp = vector.floor(get_warp_at(player_pos))
	local color
	local description = S("Local warp field: @1", minetest.pos_to_string(local_warp))
	if player_cooldown_val > 0 then
		color = hud_color_stressed
		description = description .. "\n" .. S("Cooldown: @1s", math.ceil(player_cooldown_val))
	else
		color = hud_color
	end
	local id = player_huds[player_name]
	if not id then
		id = player:hud_add({
			hud_elem_type = "text",
			position = hud_position,
			text = description,
			number = color,
			scale = 20,
		})
		player_huds[player_name] = id
	else
		player:hud_change(id, "text", description)
		player:hud_change(id, "number", color)
	end
end

local function warpfield_globalstep(dtime)
	for i, player in ipairs(minetest.get_connected_players()) do
		local player_name = player:get_player_name()
		local player_cooldown_val = math.max((player_cooldown[player_name] or 0) - dtime, 0)
		player_cooldown[player_name] = player_cooldown_val
		local wielded = player:get_wielded_item()
		if wielded:get_name() == "warpfield:trigger" then
			update_hud(player, player_name, player_cooldown_val)
		else
			hide_hud(player, player_name)
		end
	end
end

-- update hud
minetest.register_globalstep(warpfield_globalstep)


if trigger_tool_capabilities then
	minetest.register_tool("warpfield:trigger", trigger_def)
else
	minetest.register_craftitem("warpfield:trigger", trigger_def)
end

local number_of_attempts_to_use = 100
local precision = 0.1

local find_minimum = function(pos, max_tries, direction)
	direction = direction or 1
	local dir_func
	if direction > 0 then
		dir_func = vector.add
	else
		dir_func = vector.subtract
	end
	
	local last_jump = vector.new(pos)
	for i = 1, max_tries do
		local local_warp = get_warp_at(last_jump)
		local new_jump = dir_func(last_jump, local_warp)
		if vector.distance(new_jump, last_jump) < precision then
			return last_jump, i, true
		end
		last_jump = new_jump
	end
	return last_jump, max_tries, false
end

minetest.register_chatcommand("find_warp_minimum", {
	params = "[<pos>]",
	description = S("locate the nearest warpfield minimum by following the field downhill from the provided location, or from the player's location if not provided. This is where a player starting at that position will eventually wind up if they repeatedly travel by warp, not counting any falls along the way."),
	privs = {server=true},  -- Require the "privs" privilege to run
	func = function(name, param)
		local pos = nil
		local param = minetest.string_to_pos(param)
		if param then
			pos = param
		else
			local player = minetest.get_player_by_name(name)
			pos = player:get_pos()
		end
	
		local minimum, tries, success = find_minimum(pos, number_of_attempts_to_use)
		if success then
			minetest.chat_send_player(name, S("Minimum located at @1 after @2 jumps", minetest.pos_to_string(vector.round(minimum)), tries))
		else
			minetest.chat_send_player(name, S("Stopped testing for minima at @1 after @2 jumps.", minetest.pos_to_string(vector.round(minimum)), tries))
		end
	end,
})

local follow_field_array = function(name, param, direction)
	local p1, p2, step_size, round_to_nearest
	local args = param:split(" ")
	if #args == 3 or #args == 4 then
		p1 = minetest.string_to_pos(args[1])
		p2 = minetest.string_to_pos(args[2])
		step_size = tonumber(args[3])
		round_to_nearest = 1
		if #args == 4 then
			round_to_nearest = tonumber(args[4]) or 1
		end
	end
	if p1 == nil or p2 == nil or step_size == nil then
		minetest.chat_send_player(name, S('Incorrect argument format. Expected: "(x1,y1,z1) (x2,y2,z2) number [number]"'))
		return
	end
	
	local minima_hashes = {}
	local failures = 0
	local successes = 0
	for x = math.min(p1.x, p2.x), math.max(p1.x, p2.x), math.abs(step_size) do
		for y = math.min(p1.y, p2.y), math.max(p1.y, p2.y), math.abs(step_size) do
			for z = math.min(p1.z, p2.z), math.max(p1.z, p2.z), math.abs(step_size) do
				local minimum, tries, success = find_minimum({x=x,y=y,z=z}, number_of_attempts_to_use, direction)
				if success then
					successes = successes + 1
					minima_hashes[minetest.hash_node_position(vector.round(vector.divide(minimum, round_to_nearest)))] = true
				else
					failures = failures + 1
				end
				local total = successes + failures
				if total % 1000 == 0 then
					minetest.chat_send_player(name, S("Tested @1 starting points...", total))
				end
			end
		end
	end
	local sorted_minima = {}
	for hash, _ in pairs(minima_hashes) do
		table.insert(sorted_minima, vector.multiply(minetest.get_position_from_hash(hash), round_to_nearest))
	end
	table.sort(sorted_minima, function(p1, p2)
		if p1.x < p2.x then
			return true
		elseif p1.x > p2.x then
			return false
		elseif p1.y < p2.y then
			return true
		elseif p1.y > p2.y then
			return false
		elseif p1.z < p2.z then
			return true
		elseif p1.z > p2.z then
			return false
		end
		return false
	end)
	return successes, failures, round_to_nearest, sorted_minima
end

minetest.register_chatcommand("find_warp_minima", {
	params = "<minpos> <maxpos> <step_size> [<rounded_to_nearest>]",
	description = S("Find all warp minima accessible from within the given volume, starting from test points separated by step_size. These are locations that players who repeatedly teleport will eventually wind up."),
	privs = {server=true},
	func = function(name, param)
		local successes, failures, round_to_nearest, sorted_minima = follow_field_array(name, param, 1)
		minetest.chat_send_player(name, S("With @1 successful and @2 failed runs found the following minima (rounded to @3m):", successes, failures, round_to_nearest))
		for _, pos in ipairs(sorted_minima) do
			minetest.chat_send_player(name, minetest.pos_to_string(pos))
		end
	end,
})

minetest.register_chatcommand("find_warp_maxima", {
	params = "<minpos> <maxpos> <step_size> [<rounded_to_nearest>]",
	description = S("Find all warp maxima accessible from within the given volume, starting from test points separated by step_size. These are places that are difficult or impossible to reach by warpfield teleport."),
	privs = {server=true},
	func = function(name, param)
		local successes, failures, round_to_nearest, sorted_minima = follow_field_array(name, param, -1)
		minetest.chat_send_player(name, S("With @1 successful and @2 failed runs found the following maxima (rounded to @3m):", successes, failures, round_to_nearest))
		for _, pos in ipairs(sorted_minima) do
			minetest.chat_send_player(name, minetest.pos_to_string(pos))
		end
	end,
})

if minetest.get_modpath("default") then
	minetest.register_craft({
		output = "warpfield:trigger",
		recipe = {
			{"default:steel_ingot", "default:mese_crystal_fragment", "default:steel_ingot"},
			{"default:mese_crystal_fragment", "space_travel:space_drive_7", "default:mese_crystal_fragment"},
			{"default:steel_ingot", "default:mese_crystal_fragment", "default:steel_ingot"}
		}
	})
end
