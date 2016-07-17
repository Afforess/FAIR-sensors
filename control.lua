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

        if #resources > 0 then
            Log("Global resource data: %s", serpent.line(global.resources))
            Log("Total tiles explored: %d", global.tiles)
            Log("Total weighted tiles: %d", global.weighted_tiles)
            -- don't try to balance anything until a reasonable amount of the map is revealed
            if global.tiles > 500000 then
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

                    -- if we don't have at least 80% the desired amount of a resource, boost any we've found
                    if discovered > 0 and discovered < desired * 0.8 then
                        local resource_entities = table.filter(resources, function(entity) return entity.valid and entity.name == resource_name end)
                        Log("    Resource: %s  -  Entities: %d", resource_name, #resource_entities)

                        if (#resource_entities > 0) then
                            if resource_category == 'basic-solid' then
                                --rebalance_ore_patch(surface, resource_name, resource_entities, (desired - discovered) / 10)
                            else
                                rebalance_fluid_patch(surface, resource_name, resource_entities, (desired - discovered) / 10)
                            end
                        end
                    -- if we have extra of this resource, 'transmute' it into a more useful resource!
                    elseif discovered > 0 and discovered > desired * 1.5 then
                        -- try and find the resource we have the least of
                        local most_needed_resource = most_desired_resource_name(surface, resource_category, 0.7)
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
        end
    end)
end)

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

function rebalance_fluid_patch(surface, resource_name, fluid_entities, extra_amt)
    table.each(fluid_entities, function(entity)
        local amount = entity.amount
        local pos = entity.position
        local extra_fluid = math.floor(math.pow(Position.distance_squared({0, 0}, pos), 0.6))
        extra_fluid = math.min(extra_fluid, extra_amt / #fluid_entities)
        global.resources[resource_name] = global.resources[resource_name] + extra_fluid
        Log("Adding %d to fluid entity (%s:%d) at position (%s)", extra_fluid, resource_name, amount, serpent.line(pos))
        entity.amount = amount + extra_fluid
    end)
end

function find_ore_patch(surface, initial_resource_entities)
    local scan_queue = { }
    local ore_patch = { }
    local resource_name = table.first(initial_resource_entities).name
    for _, entity in pairs(initial_resource_entities) do
        table.insert(scan_queue, Tile.from_position(entity.position))
    end
    local min_ore_amt = -1
    local max_ore_amt = -1
    local total_pos = {0,0}
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

                    if entity then
                        total_pos = Position.add(total_pos, entity.position)
                        local amount = entity.amount
                        if min_ore_amt == -1 or amount < min_ore_amt then
                            min_ore_amt = amount
                        end
                        if max_ore_amt == -1 or amount > max_ore_amt then
                            max_ore_amt = amount
                        end
                    end
                end
            end
        end
    end

    local ore_entities = {}
    table.each(table.filter(ore_patch, function(tbl) return tbl.entity ~= nil end), function(tbl) table.insert(ore_entities, tbl.entity) end)

    if #ore_entities > 0 then
        local avg_position = { x = math.floor(total_pos.x / #ore_entities), y = math.floor(total_pos.y / #ore_entities) }
        return ore_entities, min_ore_amt, max_ore_amt, avg_position
    end
    return {}, -1, -1, nil
end

function rebalance_ore_patch(surface, resource_name, initial_resource_entities, extra_amt)
    local ore_entities, min_ore_amt, max_ore_amt, avg_position = find_ore_patch(surface, initial_resource_entities)
    if #ore_entities > 0 then
        local distance = Position.distance_squared({0,0}, avg_position)
        Log("Average position: %s, Distance from Origin: %s", serpent.line(avg_position), serpent.line(math.sqrt(distance)))
        local max_addition_ore =  extra_amt / #ore_entities

        local variance = math.min(35000, max_ore_amt - min_ore_amt)

        Log("Ore max amt: %d, Ore min amt: %d, variance: %d", max_ore_amt, min_ore_amt, variance)
        local avg_extra = math.min(math.floor(variance + math.random(math.max(1, variance))), max_addition_ore)
        if variance < 10 then
            avg_extra = math.floor(max_ore_amt / 2 + math.random(max_ore_amt))
        end
        -- bonus ores to small patches
        Log("Avg Extra pre-modified for distance: %s", serpent.line(avg_extra))
        avg_extra = math.floor(avg_extra * math.pow(distance, 0.8) / (#ore_entities * #ore_entities))

        local leftover_ore = extra_amt - (avg_extra * #ore_entities)
        Log("Adding an extra amount of %d to %d %s resources", avg_extra, #ore_entities, resource_name)
        Log("Leftover ore amt: %d", leftover_ore)

        global.resources[resource_name] = global.resources[resource_name] + (avg_extra * #ore_entities)
        table.each(ore_entities, function(entity)
            entity.amount = entity.amount + avg_extra
        end)

        return #ore_entities
    end
    return 0
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
    return math.floor(fair_ratios[resource_richness] * global.weighted_tiles)
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
    if not global.weighted_tiles then
        global.weighted_tiles = 0
    end
    local area_center = Area.center(area)
    -- Assumption: 0,0 is the spawn
    local dist = Position.distance({0, 0}, area_center)
    local weight = math.pow(dist, 0.57)
    global.weighted_tiles = global.weighted_tiles + (tiles * weight)
end

function increment_resource(entity)
    local entity_name = entity.name
    --Log("Amount of resource for entity %s is %s", entity_name, serpent.line(entity.amount))
    if not global.resources then
        global.resources = {}
    end
    if not global.resources[entity_name] then
        global.resources[entity_name] = 0
    end
    global.resources[entity_name] = global.resources[entity_name] + entity.amount
end
