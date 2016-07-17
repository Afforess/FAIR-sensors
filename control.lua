require 'lib/util'
require 'stdlib/event/event'
require 'stdlib/log/logger'
require 'stdlib/table'

LOGGER = Logger.new("FAIR", 'sensors', true)
local Log = function(str, ...) LOGGER.log(string.format(str, ...)) end

Event.register({Event.core_events.init, Event.core_events.configuration_changed}, function(event)
    Log("Setting up F.A.I.R EvoGUI sensors...")
    if event.data then
        Log("Mod data: %s", serpent.line(event.data))
    end
    Log("F.A.I.R Sensors setup complete.")
end)

Event.register(defines.events.on_tick, function(event)
    Event.remove(defines.events.on_tick, event._handler)
    local fair_ratios = remote.call("FAIR", "get_all_resource_fair_ratios")
    for resource_name, resource_ratios in pairs(fair_ratios) do
        local desired_amt = remote.call("FAIR", "get_resource_desired_amount", game.surfaces.nauvis, resource_name)
        local amount = remote.call("FAIR", "get_resource_amount", resource_name)

        local amt_str = "Inf.%"
        if desired_amt > 0 then
            local percent_fairness = (amount / desired_amt) * 100
            local whole_number = math.floor(percent_fairness)
            local fractional_component = math.floor((percent_fairness - whole_number) * 10)
            amt_str = string.format("%d.%d%%", whole_number, fractional_component)
        end
        local localized_name = game.entity_prototypes[resource_name].localised_name
        remote.call("EvoGUI", "create_remote_sensor", {
            mod_name = "FAIR-sensors",
            name = "FAIR-resource-" .. resource_name,
            text = {"sensor.resource.format", localized_name, amt_str},
            caption = {"sensor.resource.caption", localized_name}
        })
    end
end)

Event.register(defines.events.on_chunk_generated, function(event)
    local area = event.area
    local surface = event.surface
    -- sneaky way of running our analysis on the next tick, allows mods to do whatever they want on_chunk_generated and observe the results immediately afterword
    local gui_tick = event.tick + 2
    Event.register(defines.events.on_tick, function(event)
        if event.tick >= gui_tick then
            Event.remove(defines.events.on_tick, event._handler)

            local fair_ratios = remote.call("FAIR", "get_all_resource_fair_ratios")
            for resource_name, resource_ratios in pairs(fair_ratios) do
                local desired_amt = remote.call("FAIR", "get_resource_desired_amount", game.surfaces.nauvis, resource_name)
                local amount = remote.call("FAIR", "get_resource_amount", resource_name)

                local percent_fairness = (amount / desired_amt) * 100
                local whole_number = math.floor(percent_fairness)
                local fractional_component = math.floor((percent_fairness - whole_number) * 10)

                local localized_name = game.entity_prototypes[resource_name].localised_name
                remote.call("EvoGUI", "update_remote_sensor",
                                      "FAIR-resource-" .. resource_name,
                                      {"sensor.resource.format", localized_name, string.format("%d.%d%%", whole_number, fractional_component)})
            end

        end
    end)
end)
