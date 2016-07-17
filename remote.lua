
remote.add_interface("FAIR", {
    -- each resource should be an array of 5 values, one representing each richness level
    -- from {very-poor, poor, regular, good, and very-good}
    -- ex: set_resource_fair_ratio('coal', {1, 2, 3, 4, 5})
    set_resource_fair_ratio = function(resource_name, fair_ratios)
        global.fair_rates[resource_name] = fair_ratio
    end,

    get_resource_fair_ratios = function(resource_name)
        return global.fair_rates[resource_name]
    end,

    get_resource_amount = function(resource_name)
        return global.resources[resource_name]
    end,

    set_resource_amount = function(resource_name, amount)
        global.resources[resource_name] = amount
    end,

    get_tiles_examined = function()
        return global.tiles
    end
})
