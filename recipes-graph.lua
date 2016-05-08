#!/usr/bin/env lua

local Loader = require("loader")
local io = require("io")

recipe_colors = {
    crafting = "#cccccc",
    smelting = "#cc9999",
    chemistry = "#99cc99",
    ["oil-processing"] = "#999900",
    ["crafting-with-fluid"] = "#aaaaaa",
    ["advanced-crafting"] = "#770022",
    ["rocket-building"] = "#443355"
}
goal_attributes = {
    fillcolor="#666666",
    style='filled',
}
language = "en"
layout_engine='dot'
output_format='png'
valid_output_formats = {png=true,jpg=true,dot=true}
specific_item = nil
monolithic_graph = false
monolithic_ranksep = 1.5 -- height in inches of each row of the graph
skip_output_items = false
edge_color = false

-- some attributes are specific to certain graphviz engines, such as dot or neato
-- http://www.graphviz.org/content/attrs
graph_attributes = {
    bgcolor = 'transparent',
    rankdir = 'BT',
    -- overlap = 'false', -- need more options before enabling overlap removal
    splines = 'spline',
    model = 'subset',
    mode = 'hier',
    levelsgap = '10',
}

-- BUG: empty label is ignored by graphviz library
node_attributes = {
    label = '',
}

edge_attributes = {
    penwidth = 2,
}

-- simple command line argument processor
args_to_delete = {}
for a=1,#arg do
    if arg[a] == '-T' then
        output_format = arg[a+1]
        table.insert(args_to_delete,1,a)
        table.insert(args_to_delete,1,a+1)
    elseif arg[a] == '-i' then
        specific_item = arg[a+1]
        table.insert(args_to_delete,1,a)
        table.insert(args_to_delete,1,a+1)
    elseif arg[a] == '-m' then
        monolithic_graph = true
        table.insert(args_to_delete,1,a)
    elseif arg[a] == '--skip-output-items' then
        skip_output_items = true
        table.insert(args_to_delete,1,a)
    elseif arg[a] == '-c' then
        edge_color = true
        table.insert(args_to_delete,1,a)
    end
end
for a=1,#args_to_delete do
    table.remove(arg,args_to_delete[a])
end
-- arg is left containing a list of unrecognized arguments, which should be paths to all of the game mods

function print_usage(err)
    if(err) then
        io.stderr:write(err..'\n')
    end
    io.stderr:write([[Recipe grapher for Factorio. This is a work in progress.
Loads contents of several mods and outputs graphs of depencies for all items.

Usage:

    recipe-graph.lua [-T <type>] [-i <item>] /path/to/data/core [/path/to/data/base] [/path/to/mods/examplemod] [...]

    -T <type>
        type can be one of "png" or "jpg" or "dot"
        defaut type is "png"
    -i <item>
        item is the internal name of a single item, such as "basic-transport-belt"
        default is to output all items
    -m
        draw a single monolithic graph of every item instead of one graph per item
    --skip-output-items
        do not draw an item node for items not used in any further recipes

Examples:

This invocation produces one png for each recipe:
    recipes-graph.lua -T png /path/to/data/core /path/to/data/base

This invocation produces one jpg, only for the stone wall recipe:
    recipes-graph.lua -T jpg -i stone-wall /path/to/data/core /path/to/data/base

This invocation produces one dot file for each recipe:
    recipes-graph.lua -T dot /path/to/data/core /path/to/data/base

If you have other mods installed, their paths can be added to the end of the command line:
    recipes-graph.lua /path/to/data/core /path/to/data/base /path/to/mods/Industrio /path/to/mods/DyTech    

]])
end

if(valid_output_formats[output_format]==nil) then
    print_usage('Invalid output type specified')
    os.exit()
end

if pcall(function () require ("gv") end) then
else
    print_usage('graphviz lua lib not available')
    os.exit()
end

-- http://www.wowwiki.com/USERAPI_StringHash
function StringHash(text)
  local counter = 1
  local len = string.len(text)
  for i = 1, len, 3 do 
    counter = math.fmod(counter*8161, 4294967279) +  -- 2^32 - 17: Prime!
      (string.byte(text,i)*16776193) +
      ((string.byte(text,i+1) or (len-i+256))*8372226) +
      ((string.byte(text,i+2) or (len-i+256))*3932164)
  end
  return math.fmod(counter, 4294967291) -- 2^32 - 5: Prime (and different from the prime in the loop)
end

function color_from_name (name)
    hash = StringHash(name)
    -- "H.ue S.at V.al"
    return ((hash%1000)/1000) .. " " .. ((math.floor(hash/1000)%1000)/2000+0.5) .. " " .. (0.5-(math.floor(hash/1000000)%1000)/2000+0.3)
end

Ingredient = {}
function Ingredient:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

function Ingredient.from_recipe(spec)
    local self = Ingredient:new()
    if spec.type == nil then
       
        self.type = "item"
        
        self.name = spec[1]
        self.amount = spec[2]
    else
        self.type = spec.type
        self.name = spec.name
        self.amount = spec.amount
    end
    
     if string.find(self.name,"science") then
            --print("***this is a science pack " .. spec[1] .. " converting to item")
            -- for some reason science packs are 'tools' in the item.lua spec
            self.type = "tool"
        
        end
    
    self:_make_id()

    
    -- if string.find(self.name,"science") then
    --     print("***this is a science pack " .. self.type .. " " .. self.name)
    -- end
    if self.type == "item" then
        
        for k, type in ipairs(Loader.item_types) do
            --print("Trying to load " .. type .. self.name)
            
            
            --print(k .." ".. type .. " " .. self.name)
            self.item_object = Loader.data[type][self.name]
            if self.item_object ~= nil then break end
        end
    else
        -- if string.find(self.name,"science") then
        --     print(self.type .. " " .. self.name)
        -- end
        self.item_object = Loader.data[self.type][self.name]
        -- if self.item_object then
        --     print("found")
        --     print(self.item_object.icon)
        -- else
        --     print("not found")
        -- end
    end

    if not self.item_object then
        --print("Creating " ..  self.name)
        ---error(self.type .. " " .. self.name .. " doesn't exist!")
        print(self.type .. " " .. self.name .. " doesn't exist!")
    else
        -- if string.find(self.name,"science") then
        --     print(self.type .. " " .. self.name .. " " .. self.item_object.icon)
        -- end
        self.image = Loader.expand_path(self.item_object.icon)
    end

    

    return self
end

function Ingredient:_make_id()
    if string.find(self.name,"science") then
        print("Making name for " .. self.type .. " " .. self.name)
    end
    self.id = self.type .. "-" .. self.name
end

function Ingredient:translated_name(language)
    if string.find(self.name,"science") then
        print("Trnslated name for " .. self.type .. " " .. self.name)
    end
   
    local item_name = Loader.translate(self.type .. "-name." .. self.name, language)
    if item_name then
        return item_name
    end



    if self.item_object.place_result then
        return Loader.translate("entity-name." .. self.item_object.place_result, language)
    
    elseif self.item_object.placed_as_equipment_result then
        return Loader.translate("equipment-name." .. self.item_object.placed_as_equipment_result, language)
    else
        item_name = Loader.translate("item" .. "-name." .. self.name, language)
        if item_name then
            return item_name
        else
            return self.name
        end
    end
end

Recipe = {}
function Recipe:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

function Recipe.from_data(spec, name)
    local self = Recipe:new()
    self.name = name
    self.id = 'recipe-' .. name
    self.category = spec.category or "crafting"
    self.ingredients = {}
    self.type = spec.type
    
    
    -- if string.find(self.name,"science") then
    --     print("***this is a science pack " .. " " .. self.name .. " " .. self.type)
    
    --     -- for k,v in pairs(spec) do
    --     --     print(k .. ' ' .. v)
    --     -- end
    -- end
    
    for k, v in ipairs(spec.ingredients) do
        
        self.ingredients[#self.ingredients + 1] = Ingredient.from_recipe(v)
    end
    if spec.results ~= nil then
        self.results = {}
        for k, v in ipairs(spec.results) do
            self.results[#self.results + 1] = Ingredient.from_recipe(v)
        end
    else
        self.results = { Ingredient.from_recipe{spec.result, (spec.result_count or 1)} }
    end
    return self
end

function Recipe:translated_name(language)
    return Loader.translate("recipe-name." .. self.name, language) or self.results[1]:translated_name(language)
end

function enumerate_resource_items()
    -- populate complete list of resource items

    resource_items = {}
    for name, resource in pairs(Loader.data.resource) do
        if resource.minable.results ~= nil then
            for k, v in ipairs(resource.minable.results) do
                resource_items[Ingredient.from_recipe(v).id] = 1
            end
        else
            resource_items[Ingredient.from_recipe{resource.minable.result, 1}.id] = 1
        end
    end
end

function enumerate_recipes()
    -- populate complete list of recipes and their ingredients

    recipes_by_result = {}
    for name, recipe in pairs(Loader.data.recipe) do
        -- if string.find(name,"science") then
        --     print("***this is a science pack " .. name)
        -- end
        recipe = Recipe.from_data(recipe, name)
        --print(name)
        for k, result in ipairs(recipe.results) do
            --print('>>' .. result.id)
            --print(result[2])
            --print(result[1])
            if recipes_by_result[result.id] == nil then
                recipes_by_result[result.id] = { recipe }
                
            else
                recipes_by_result[result.id][#recipes_by_result[result.id] + 1] = recipe
            end
        end
    end
end

function find_recipe(result)
    -- argument is an ingredient, but we ignore amount
    local ret
    for name, recipe in pairs(Loader.data.recipe) do
        recipe = Recipe.from_data(recipe, name)
        for k, v in ipairs(recipe.results) do
            if v.type == result.type and v.name == result.name then
                if ret ~= nil then
                    --error
                    print("multiple recipes with the same result (" .. ret_recipe.name .. " and " .. recipe.name .. ")")
                end
                ret = recipe
                ret.amount = result.amount / v.amount
            end
        end
    end

    return ret
end

function add_item_port(list, item, port)
    if list[item.id] == nil then
        list[item.id] = { port }
    else
        list[item.id][#list[item.id] + 1] = port
    end
end

function recipe_node(graph, recipe, closed, goal_items, item_sources, item_sinks)
    if recipe_colors[recipe.category] == nil then
        --error
        print(recipe.category .. " is not a known recipe category (add it to recipe_colors)")
    else
    
        node = gv.node(graph, recipe.id)
        gv.setv(node, 'shape', 'plaintext')
        gv.setv(node, 'xlabel', 'xxxx' .. ' / s')
   
        local label = ''
        local colspan = 0
        label = label .. '<<TABLE bgcolor = "' .. recipe_colors[recipe.category] .. '" border="0" cellborder="1" cellspacing="0"><TR>\n'
        for k, result in ipairs(recipe.results) do
            label = label .. '<TD port="' .. result.id .. '"><IMG src="' .. result.image .. '" /></TD>\n'
            --if result.ingredients ~= nil then
            --    print(#result.ingredients)
            --end
            add_item_port(item_sources, result, {recipe.id,result.id .. ':n'})
            colspan = colspan + 1
            
            print("colspan=" .. colspan .. " " .. recipe.id .. " " .. recipe.category .. " x" .. result.amount)
            
        end
        label = label .. '</TR><TR><TD colspan="' .. colspan .. '">' .. recipe:translated_name(language) .. '</TD>'
        label = label .. '</TR></TABLE>>'

        gv.setv(node, 'label', label)

        for k, ingredient in ipairs(recipe.ingredients) do
            add_item_port(item_sinks, ingredient, {recipe.id})

            if not closed[ingredient.id] then
                goal_items[#goal_items + 1] = ingredient
            end
            
            print(ingredient.id .. ' x' .. ingredient.amount)
        end
    end
    return node
end

function item_node(graph, item_id, goal)
    --print('**item_node ' .. item_id)
    local type, name = item_id:match('^(%a+)-(.*)$')
    ingredient = Ingredient.from_recipe{type = type, name = name, amount = 1}
    node = gv.node(graph, ingredient.id)
    gv.setv(node, 'image', ingredient.image)
    gv.setv(node, 'xlabel', ingredient.amount .. ' / s')
   
    -- if the item is a goal item then apply the goal attributes to the node
    if(goal) then
        if type == goal.type and name == goal.name then
            for attr,value in pairs(goal_attributes) do
                gv.setv(node, attr, value)
            end
        end
    end
    return node
end

function output_graph(goal_items)
    -- use 'factorio' as the output file name if monolithic_graph else the goal_item id
    local graphname = (monolithic_graph) and 'factorio' or (goal_items[1].id)
    local graph = gv.digraph(graphname)

    
    if(monolithic_graph) then
        -- set row height in graph
        gv.setv(graph, 'ranksep', monolithic_ranksep)
    else
        -- make the first goal item the root node ??
        gv.setv(graph, 'root', goal_items[1].id)
    end
    
    
    
    -- apply default graph attributes to new graph
    for attr,value in pairs(graph_attributes) do
        gv.setv(graph, attr, value);
    end
    
    -- apply default node attributes to each proto node of the graph ?
    for attr,value in pairs(node_attributes) do
        gv.setv(gv.protonode(graph), attr, value);
    end
    -- apply default edge attributes to each proto edge of the graph ?
    for attr,value in pairs(edge_attributes) do
        gv.setv(gv.protoedge(graph), attr, value);
    end

    -- convert transparent to white for jpg output
    if(output_format=='jpg' and graph_attributes.bgcolor=='transparent') then
        gv.setv(graph, 'bgcolor', 'white')
    end
    


    local closed = {}
    local item_sources = {}
    local item_sinks = {}

    local i=0
    -- loop through goal items
    while i<#goal_items do
        i=i+1
        local current = goal_items[i]
        -- print("current = " .. current.id)
        if closed[current.id] == nil then
            closed[current.id] = current
        end

        if(string.find(current.id,"science"))then
            print("Checking sources and recipe lists for " .. current.id)
            print(resource_items[current.id])
            print((recipes_by_result[current.id] ~= nil and #recipes_by_result[current.id] or 0) .. " recipes")
        end
        -- if current is a resource and used in at least one recipe
        if not resource_items[current.id] and recipes_by_result[current.id] ~= nil then
            for k, recipe in pairs(recipes_by_result[current.id]) do
                if not closed[recipe.id] then
                    recipe_node(graph, recipe, closed, goal_items, item_sources, item_sinks)
                    closed[recipe.id] = 1
                end
            end
        elseif (item_sources[current.id]==nil and item_sinks[current.id]==nil) then
            -- add a node for items not part of any recipe
            -- usually this is when trying to draw a graph for a raw resource
            item_node(graph, current.id, current)
        end
    end

    for id, source_ports in pairs(item_sources) do
        for k, source_port in pairs(source_ports) do
            sink_ports = item_sinks[id]
            if sink_ports then
                -- if item has at least one sink port
                for k, sink_port in ipairs(sink_ports) do
                    local edge = gv.edge(graph, source_port[1], sink_port[1])
                    if(edge_color) then
                        gv.setv(edge, 'color', color_from_name(source_port[1]))
                    end
                    if (source_port[2]) then
                        gv.setv(edge,'tailport',source_port[2])
                    end
                    if (sink_port[2]) then
                        gv.setv(edge,'headport',sink_port[2])
                    end
                    gv.setv(edge, 'xlabel', 'yyyy' .. ' / s')
   
                end
            else
                --final output items
                
                -- skip_output_items will skip over items not used in any recipes
                if(not skip_output_items) then
                    item_node(graph, id, (not monolithic_graph) and goal_items[1] or nil)
                    local edge = gv.edge(graph, source_port[1], id)
                    if(edge_color) then
                        gv.setv(edge, 'color', color_from_name(source_port[1]))
                    end
                    gv.setv(edge,'weight','1000')
                    if (source_port[2]) then
                        gv.setv(edge,'tailport',source_port[2])
                    end
                    
                    gv.setv(node, 'xlabel', 'zzzz' .. ' / s')
   
                end
            end
        end
    end

    -- create edges between id and sink port???
    for id, sink_ports in pairs(item_sinks) do
        for k, sink_port in pairs(sink_ports) do
            if item_sources[id] == nil then
                item_node(graph, id, #goal_items==1 and goal_items[1] or nil)
                gv.edge(graph, id, sink_port[1])
                gv.setv(edge,'weight','100')
                if (sink_port[2]) then
                    gv.setv(edge,'headport',sink_port[2])
                end
                
                gv.setv(node, 'xlabel', 'jjjjj' .. ' / s')
   
            end
        end
    end

    -- write output file
    if(output_format=='png' or output_format=='jpg') then
        -- if not writing a monolithic_graph output the name of the goal item only
        if(not monolithic_graph) then
            print(goal_items[1].id)
        end
        gv.layout(graph, layout_engine)
        gv.render(graph, output_format, graphname .. '.' .. output_format)
    else
        if(not (output_format=='dot')) then
            io.stderr:write('Unknown output format "'..output_format..'". Falling back to dot.\n')
        end
        gv.layout(g, 'dot')
        gv.write(graph, graphname .. '.dot')
    end
end

Loader.load_data(arg, "en")
enumerate_resource_items()
enumerate_recipes()

graphs_generated = 0
item_list = {}

table.insert(Loader.item_types,"fluid")
table.insert(Loader.item_types,"tool")
for k, item_type in ipairs(Loader.item_types) do
    for name, item in pairs(Loader.data[item_type]) do
        if(specific_item == nil or specific_item == name) then
            if(monolithic_graph) then
                table.insert(item_list,Ingredient.from_recipe{name = name, type=(item_type=="fluid") and "fluid" or (item_type=="tool") and "tool" or "item" , amount=1})
            else
                graphs_generated = graphs_generated + 1
                output_graph({Ingredient.from_recipe{name = name, type=(item_type=="fluid") and "fluid" or (item_type=="tool") and "tool" or "item" , amount=1}})
            end
        end
    end
end

if(monolithic_graph) then
    output_graph(item_list)
    graphs_generated = graphs_generated + 1
end

if(graphs_generated == 0) then
    if(specific_item ==nil) then
        io.stderr:write('No graphs generated. Something is wrong.\n')
    else
        io.stderr:write('Item "'..specific_item..'" not found. No graph generated.\n')
    end
else
    print('Generated '..graphs_generated..' graphs.')
end