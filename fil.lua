-- sets the sets  described by @t, a table {[emitter]={ev1,ev2,...},...} (creating them if @val~=nil)
-- @obj entries to @val
local next,setmetatable=next,setmetatable


Fil=setmetatable({},{__tostring='Class Fil'})
Fil.meta={
	__index=Fil,
	__tostring=function(t)
		local meta=getmetatable(t)
		setmetatable(t,nil)
		local s=stringify(t,nil,nil,nil,nil,3)
		setmetatable(t,meta)
		return s
	end,
}

Fil.new=function()
	return setmetatable({},Fil.meta)
end

Fil.multiset = function (fil,t,val) 
	if val~=nil then
		for emitter,events in pairs(t) do
			local eml=fil[emitter]
			if not eml then
				eml={}
				fil[emitter]=eml
			end
			local event
			for i=1,#events do
				event=events[i]
				eml[event]=val
			end
		end
	else
		for emitter,events in pairs(t) do
			local eml=fil[emitter]
			if eml then
				local event
				for i=1,#events do
					event=events[i]
					eml[event]=val
				end
				if not next(eml) then fil[emitter]=nil end
			end
		end
	end
	return true
end

Fil.get=function(fil,em,ev)
	if fil[em] then return fil[em][ev] end
end

-- Fil.iter=function(fil)
	-- local em,ev
	-- if val~=nil then
		-- for emitter,events in pairs(t) do
			-- local eml=fil[emitter]
			-- if not eml then
				-- eml={}
				-- fil[emitter]=eml
			-- end
			-- local event
			-- for i=1,#events do
				-- event=events[i]
				-- eml[event]=val
			-- end
		-- end
	-- else
		-- for emitter,events in pairs(t) do
			-- local eml=fil[emitter]
			-- if eml then
				-- local event
				-- for i=1,#events do
					-- event=events[i]
					-- eml[event]=val
				-- end
				-- if not next(eml) then fil[emitter]=nil end
			-- end
		-- end
	-- end
-- end
---same, but accepts only the alternate description of emitter,event
Fil.uniset = function (fil,emitter,event,val)
	local eml=fil[emitter]
	if val~=nil then
		if not eml then
			eml={}
			fil[emitter]=eml
		end
		eml[event]=val
	else
		if eml then
			eml[event]=nil
		end
	end
end
return Fil