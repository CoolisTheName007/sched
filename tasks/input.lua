local sched=require'packages.sched'
local input=sched.Obj.new('input'):setParent()
local timeout=0.10
local extra=0.6
local os_time=os.clock
local pipe=require'packages.sched.pipe'


do
	---This do-block adapted from
	---Gopher
	--ctrl+' is glitchy
	--ctrlkey events
	 
	local keyToChar      = {[2]="1",[3]="2",[4]="3",[5]="4",[6]="5",[7]="6",[8]="7",[9]="8",[10]="9",[11]="0",[12]="-",[13]="=",[16]="q",[17]="w",[18]="e",[19]="r",[20]="t",[21]="y",[22]="u",[23]="i",[24]="o",[25]="p",[26]="[",[27]="]",[30]="a",[31]="s",[32]="d",[33]="f",[34]="g",[35]="h",[36]="j",[37]="k",[38]="l",[39]=";",[40]="'",          [43]="\\",[44]="z",[45]="x",[46]="c",[47]="v",[48]="b",[49]="n",[50]="m",[51]=",",[52]=".",[53]="/",}
	local keyToCharShift = {[2]="!",[3]="@",[4]="#",[5]="$",[6]="%",[7]="^",[8]="&",[9]="*",[10]="(",[11]=")",[12]="_",[13]="+",[16]="Q",[17]="W",[18]="E",[19]="R",[20]="T",[21]="Y",[22]="U",[23]="I",[24]="O",[25]="P",[26]="{",[27]="}",[30]="A",[31]="S",[32]="D",[33]="F",[34]="G",[35]="H",[36]="J",[37]="K",[38]="L",[39]=":",[40]="\"",[41]="~",[43]="|", [44]="Z",[45]="X",[46]="C",[47]="V",[48]="B",[49]="N",[50]="M",[51]="<",[52]=">",[53]="?",}
	local charToKey = {["P"]=25,["S"]=31,["R"]=19,["U"]=22,["T"]=20,["W"]=17,["V"]=47,["Y"]=21,["X"]=45,["["]=26,["Z"]=44,["]"]=27,["\\"]=43,["_"]=12,["^"]=7,["a"]=30,["c"]=46,["b"]=48,["e"]=18,["d"]=32,["g"]=34,["f"]=33,["i"]=23,["h"]=35,["k"]=37,["j"]=36,["m"]=50,["l"]=38,["o"]=24,["n"]=49,["q"]=16,["p"]=25,["s"]=31,["r"]=19,["u"]=22,["t"]=20,["w"]=17,["v"]=47,["y"]=21,["x"]=45,["{"]=26,["z"]=44,["}"]=27,["|"]=43,["~"]=41,["!"]=2,["#"]=4,["\""]=40,["%"]=6,["$"]=5,["'"]=40,["&"]=8,[")"]=11,["("]=10,["+"]=13,["*"]=9,["-"]=12,[","]=51,["/"]=53,["."]=52,["1"]=2,["0"]=11,["3"]=4,["2"]=3,["5"]=6,["4"]=5,["7"]=8,["6"]=7,["9"]=10,["8"]=9,[";"]=39,[":"]=39,["="]=13,["<"]=51,["?"]=53,[">"]=52,["A"]=30,["@"]=3,["C"]=46,["B"]=48,["E"]=18,["D"]=32,["G"]=34,["F"]=33,["I"]=23,["H"]=35,["K"]=37,["J"]=36,["M"]=50,["L"]=38,["O"]=24,["N"]=49,["Q"]=16,}
	 
	 
	
		local lastInCtrl, lastInCtrlShift=false,false
		local prevKey=0
		local pasting=false
		local state
		
		sched.sighook(
			'ctrl_key_producer',
			function(_,e,p1,p2,p3)
				if state then
					-- print'state'
					if e~="char" or charToKey[p1]~=state then
					  sched.signal(input,"ctrl_key",state,lastInCtrlShift and keyToCharShift[state] or keyToChar[state],lastInCtrlShift)        
					end
					lastInCtrlShift=false
					lastInCtrl=false
					
					prevKey=state
					pasting=false
					
					-- print'state_out'
					state=false
					
				elseif e=="key" then
					-- print'key'
				  if p1==keys.leftCtrl or p1==keys.rightCtrl then
					lastInCtrl=true
					lastInCtrlShift=false
					lastInCtrlAlt=false
				  elseif p1==keys.leftShift or p1==keys.rightShift and lastInCtrl then
					-- print'shift'
					lastInCtrlShift=true
				  elseif p1==keys.leftAlt or p1==keys.rightAlt and lastInCtrl then
					-- print'alt'
					lastInCtrlAlt=true
				  else
					if lastInCtrl and keyToCharShift[p1] then
						sched.running:setTimeout(0.05)
						state=p1
					else
						prevKey=p1
						pasting=false
					end
				  end
				 
				elseif e=="char" then
					-- print'char'
				  if not pasting and charToKey[p1]~=prevKey then
					--paste begin, send a ctrl-t event
					sched.signal(input,"ctrl_key",keys.t,lastInCtrlShift and "V" or "v",lastInCtrlShift,lastInCtrlAlt)
					pasting=true
					sched.running:setTimeout(0.05)
				  end
				  lastInCtrlShift=false
				  lastInCtrlAlt=false
				  lastInCtrl=false
				elseif e=="timer" then
					-- print'timer'
					pasting=false
				end
			end,
		{platform={'key','char'}}
		)
end


input.set=function(_timeout,_extra)
	timeout,extra=_timeout,_extra
end
do
	local timer
	function input.char_handle(obj,em,ev,n)
		if em=='timer' then
			sched.signal(input,'charup',input.char)
			input.char=false
		else
			if not input.char then
				timer=os_time()
				input.chars[n]=timer
				obj:link{timer={timer+timeout}}
				input.char=n
				sched.signal(input,'chardown',n)
			else
				if timer then obj:unlink{timer={timer+timeout}} end
				timer=os_time()
				input.chars[n]=timer
				obj:link{timer={timer+timeout}}
			end
		end
	end
end
do
	local timer
	function input.key_handle(obj,em,ev,n)
		if em=='timer' then
			sched.signal(input,'keyup',input.key)
			input.key=false
		else
			if not input.key then
				timer=os_time()
				input.keys[n]=timer
				obj:link{timer={timer+timeout}}
				input.key=n
				sched.signal(input,'keydown',n)
			else
				if timer then obj:unlink{timer={timer+timeout}} end
				timer=os_time()
				input.keys[n]=timer
				obj:link{timer={timer+timeout}}
			end
		end
	end
end

input._reset=function()
	input.key=nil
	input.char=nil
	input.keys={}
	input.chars={}
	sched.Obj.new('keyupdownproducer'):link{platform={'key'}}:setParent(input).handle=input.key_handle
	sched.Obj.new('charupdownproducer'):link{platform={'char'}}:setParent(input).handle=input.char_handle
	input.pipe=pipe()
	sched.Obj.new('inputredirect'):link{
	platform={
	'char',
	'key',
	'mouse_click',
	'mouse_scroll',
	'mouse_drag',}
	--'monitor_touch'},
	}:setParent(input).handle=function(_,__,...)
		sched.signal(input,...)
	end
end

input._reset()
return input