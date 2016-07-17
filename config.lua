CONFIG = {}
CONFIG.fair_ratios =
{
    -- amount of resource per total resources discovered
    -- e.g 1 -> 1 resource per N total, where N is the sum of all resource numbers
    -- ex: 1 + 2 + 1 + 1 + 3 = coal should be one of every 8 resources discovered
    -- each resource should be an array of 5 values, one representing each richness level
    -- from {very-low, low, normal, high, and very-high}
    coal = {["very-low"] = 1, low = 2, normal = 4, high = 6, ["very-high"] = 8},
    ["iron-ore"] = {["very-low"] = 2, low = 4, normal = 6, high = 8, ["very-high"] = 10},
    ["copper-ore"] = {["very-low"] = 3, low = 5, normal = 8, high = 11, ["very-high"] = 15},
    stone = {["very-low"] = 1, low = 2, normal = 4, high = 6, ["very-high"] = 8}
}
