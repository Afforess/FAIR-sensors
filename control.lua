require 'config'
require 'lib/util'
require 'stdlib/area/area'
require 'stdlib/area/position'
require 'stdlib/area/tile'
require 'stdlib/event/event'
require 'stdlib/log/logger'
require 'stdlib/table'

LOGGER = Logger.new("FAIR", 'main', true)
local Log = function(str, ...) LOGGER.log(string.format(str, ...)) end

Event.register({Event.core_events.init, Event.core_events.configuration_changed}, function(event)
    Log("Setting up F.A.I.R...")
    if event.data then
        Log("Mod data: %s", serpent.line(event.data))
    end

    if not global.fair_rates then
        global.fair_rates = {}
    end
    for resource_name, ratios in pairs(CONFIG.fair_ratios) do
        global.fair_rates[resource_name] = ratios
    end
    Log("F.A.I.R setup complete.")
end)

Event.register(defines.events.on_chunk_generated, function(event)
    local area = event.area
    local surface = event.surface
    -- sneaky way of running our analysis on the next tick, allows mods to do whatever they want on_chunk_generated and observe the results immediately afterword
    Event.register(defines.events.on_tick, function(event)
        Event.remove(defines.events.on_tick, event._handler)

        local resources = surface.find_entities_filtered({area = area, type = 'resource'})
        table.each(resources, increment_resource)
        increment_tiles(area)

        if #resources > 0 and global.tiles > 500000 then
            analyze_resources(surface, area, resources)
        end
    end)
end)

function analyze_resources(surface, area, resources)
    Log("Global resource data: %s", serpent.line(global.resources))
    Log("Total tiles explored: %d", global.tiles)
    -- don't try to balance anything until a reasonable amount of the map is revealed
    Log("Desired resource amounts: ")
    for resource_name, ratios in pairs(global.fair_rates) do
        local discovered = 0
        if global.resources[resource_name] then
            discovered = global.resources[resource_name]
        end
        local desired = resource_desired_amt(surface, resource_name)
        local resource_category = game.entity_prototypes[resource_name].resource_category
        Log("    Resource: %s  -      Amount: %d", resource_name, desired)
        Log("    Resource: %s  -  Discovered: %d", resource_name, discovered)

        -- if we have extra of this resource, 'transmute' it into a more useful resource!
        if discovered > 0 and discovered > desired * 1.5 then
            -- try and find the resource we have the least of
            local most_needed_resource = most_desired_resource_name(surface, resource_category, 0.8)
            if most_needed_resource then
                local resource_entities = table.filter(resources, function(entity) return entity.valid and entity.name == resource_name end)
                Log("    Resource: %s  -  Entities: %d", resource_name, #resource_entities)

                if (#resource_entities > 0) then
                    if resource_category == 'basic-solid' then
                        transmute_ore_patch(surface, most_needed_resource, resource_entities)
                    else
                        -- unsupported
                    end
                end
            end
        end
    end
end

function transmute_ore_patch(surface, new_resource_name, initial_resource_entities)
    local total_amt = 0
    local initial_resource = table.first(initial_resource_entities).name
    local ore_patch = find_ore_patch(surface, initial_resource_entities)
    table.each(ore_patch, function(resource_entity)
        local amt = resource_entity.amount
        local pos = resource_entity.position
        local force = resource_entity.force
        global.resources[initial_resource] = global.resources[initial_resource] - amt
        global.resources[new_resource_name] = global.resources[new_resource_name] + amt

        total_amt = total_amt + amt

        resource_entity.destroy()
        surface.create_entity({name = new_resource_name, force = force, position = pos, amount = amt})
    end)
    Log("Transmuted %d:%d ores of %s into %s", #ore_patch, total_amt, initial_resource, new_resource_name)
end

function most_desired_resource_name(surface, resource_category, min_ratio)
    local best_ratio = min_ratio
    local best_resource = nil
    for resource_name, ratio in pairs(global.fair_rates) do
        if game.entity_prototypes[resource_name].resource_category == resource_category then
            local desired_resource_amt = resource_desired_amt(surface, resource_name)
            local discovered_resource_amt = global.resources[resource_name]
            local fairness_ratio = discovered_resource_amt / desired_resource_amt
            Log("Fairness ratio of resource %s is %s", resource_name, fairness_ratio)
            if fairness_ratio < best_ratio then
                best_resource = resource_name
                best_ratio = fairness_ratio
            end
        end
    end
    return best_resource
end

function find_ore_patch(surface, initial_resource_entities)
    local scan_queue = { }
    local ore_patch = { }
    local resource_name = table.first(initial_resource_entities).name
    for _, entity in pairs(initial_resource_entities) do
        table.insert(scan_queue, Tile.from_position(entity.position))
    end
    while(#scan_queue > 0) do
        local pos = table.remove(scan_queue)
        local key = pos_key(pos)
        if not ore_patch[key] or ore_patch[key].entity then
            for _, adj_pos in pairs(Tile.adjacent(surface, pos, true)) do
                local key = pos_key(adj_pos)
                if not ore_patch[key] then
                    local entity = find_ore_entity(surface, resource_name, adj_pos)
                    ore_patch[key] = { pos = adj_pos, entity = entity }
                    table.insert(scan_queue, adj_pos)
                end
            end
        end
    end

    local ore_entities = {}
    table.each(table.filter(ore_patch, function(tbl) return tbl.entity ~= nil end), function(tbl) table.insert(ore_entities, tbl.entity) end)

    return ore_entities
end

function find_ore_entity(surface, resource_name, position)
    local area = Position.expand_to_area(Position.offset(Tile.from_position(position), 0.5, 0.5), 0.4)
    local entities = surface.find_entities_filtered({name = resource_name, area = area})
    if #entities > 0 then
        return table.first(entities)
    end
    return nil
end

function pos_key(pos)
    return bit32.bor(bit32.lshift(bit32.band(pos.x, 0xFFFF), 16), bit32.band(pos.y, 0xFFFF))
end

function resource_desired_amt(surface, resource_name)
    if not global.fair_rates[resource_name] then
        return 0
    end
    local controls = surface.map_gen_settings.autoplace_controls
    if not controls[resource_name] then
        return 0
    end
    local fair_ratios = global.fair_rates[resource_name]
    local resource_richness = controls[resource_name].richness

    local total_amt = 0
    for _, resource_amt in pairs(global.resources) do
        total_amt = total_amt + resource_amt
    end
    return math.floor(fair_ratios[resource_richness] * total_amt)
end

function is_spawn_area(area)
    return Area.inside({{-128, -128}, {128, 128}}, area.left_top) or Area.inside({{-128, -128}, {128, 128}}, area.right_bottom)
end

function increment_tiles(area)
    if not global.tiles then
        global.tiles = 0
    end
    local tiles = Area.area(area)
    global.tiles = global.tiles + tiles
end

function increment_resource(entity)
    local entity_name = entity.name
    if not global.resources then
        global.resources = {}
    end
    if not global.resources[entity_name] then
        global.resources[entity_name] = 0
    end
    global.resources[entity_name] = global.resources[entity_name] + entity.amount
end
