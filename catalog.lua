--- A general purpose Catalog.
-- The catalog is used to give tasks well known names for sharing purposes. 
-- It also allows synchronization, by blocking the requester until the object
-- is made available. Catalogs themselves are made available under a Well Known
-- name. Typical catalogs are "tasks", "mutexes" and "pipes".
-- The catalog does not check for multiple names per object.
-- @module catalog
-- @usage local tasks = require 'catalog'.get_catalog('tasks')
--...
--tasks:register('a task', sched.Task.running)
--...
--local a_task=tasks:waitfor('a task')
-- @alias M

local log = require 'packages.log'
local check=require'packages.checker'.check
local sprint=require'packages.print'.sprint

PACKAGE_NAME = 'sched'

local sched=require'init'


--get locals for some useful things
local next,  setmetatable, tostring, getmetatable
	= next,  setmetatable, tostring, getmetatable

local M = {}

local rev = setmetatable({}, {__mode = "kv"}) --tables of object->name in catalogs indexed by catalogs

local catalogs = setmetatable({},{__mode = "v",__tostring=function() return 'catalogs' end,__type='catalog'})
rev[catalogs]={}
rev[catalogs][catalogs]='catalogs'

local register_events = setmetatable({}, {__mode = "kv"}) 
function get_register_event (catalogd, name)
	check('catalog,string',catalogd, name)
	if register_events[catalogd] and register_events[catalogd][name] then 
		return register_events[catalogd][name]
	else
		local register_event = setmetatable({}, {
			__tostring=function() return 'register$'..rev[catalogs][catalogd]..'/'..name end,
		})
		register_events[catalogd] = register_events[catalogd] or {}
		register_events[catalogd][name] = register_event
		return register_event
	end
end



--- Register a name to a object
-- @param catalogd the catalog to use.
-- @param name a name for the object
-- @param object the object to name.
-- @return true is successful; nil, 'used' if the name is already used by another object.
M.register = function ( catalogd, name, object )
	check('catalog,string',catalogd,name)
	if catalogd[name] and catalogd[name] ~= object then
		return nil, 'used'
	end
	print(rev,catalogd,object)
	log('CATALOG', 'INFO', '%s registered in catalog %s as "%s"', 
		tostring(object), rev[catalogs][catalogd], name)
	catalogd[name] = object
	rev[catalogd][object]=name
	
	sched.signal('catalog',get_register_event(catalogd, name),object) 
	return true
end

--- Retrieve a object with a given name.
-- Can wait up to timeout until it appears.
-- @param catalogd the catalog to use.
-- @param name name of the object
-- @param timeout time to wait. nil or negative waits for ever.
-- @return the object if successful or nil in case of timeout
M.waitfor = function ( catalogd, name, timeout )
	check('catalog,string,?number',catalogd,name,timeout)
	log('CATALOG', 'INFO', 'catalog %s queried for name "%s" by %s',tostring(catalogd), name,tostring(sched.me()))
	local object=catalogd[name] or select(3,sched.wait('catalog', get_register_event(catalogd, name),timeout))
	log('CATALOG', 'INFO', 'catalog %s queried for name "%s" by %s, found %s',tostring(catalogd), name,tostring(sched.me()),tostring(object))
	return object 
end

--- Retrieve a catalog.
-- Catalogs are created on demand
-- @param name the name of the catalog.
M.get_catalog = function (name)
	check('string',name)
	if catalogs[name] then 
		return catalogs[name] 
	else
		local catalogd = setmetatable({}, { __mode = 'v', __type='catalog',__tostring=function() return name end,__index=M})
		rev[catalogd]={}
		M.register(catalogs,name,catalogd)
		return catalogd
	end
end

M.reset = function ()
	rev = setmetatable({}, {__mode = "kv"}) --tables of object->name in catalogs indexed by catalogs

	catalogs = setmetatable({},{__mode = "v",__tostring=function() return 'catalogs' end,__type='catalog'})
	rev[catalogs]={}
	rev[catalogs][catalogs]='catalogs'
end

setmetatable(M,{__call=function(M,...)
	local nargs=select('#',...)
	if nargs==3 then
		check('catalog,string',catalogd,name)
		return M.register(...)
	elseif nargs==1 then
		check('string',...)
		return M.get_catalog(...)
	end
end})

return M


