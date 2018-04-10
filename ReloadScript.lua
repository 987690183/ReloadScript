
--[[
	加载脚本
	用于开发阶段时编辑逻辑代码，不用重启，看效果
]]

local ReloadScript = {}
ReloadScript.Lua = UnityEngine.Application.dataPath.."/Lua"

local FileNameList = {
    "_ALL_",
}

function ReloadScript.FailNotify(...)
	if ReloadScript.NotifyFunc then ReloadScript.NotifyFunc(...) end
end

function ReloadScript.DebugNofity(...)
	if ReloadScript.DebugNofityFunc then ReloadScript.DebugNofityFunc(...) end
end

local function GetWorkingDir()
	if ReloadScript.WorkingDir == nil then
	    local p = io.popen("echo %cd%")
	    if p then
	        ReloadScript.WorkingDir = p:read("*l").."\\"
	        p:close()
	    end
	end
	return ReloadScript.WorkingDir
end

local function Normalize(path)
	path = path:gsub("/","\\") 
	if path:find(":") == nil then
		path = GetWorkingDir()..path 
	end
	local pathLen = #path 
	if path:sub(pathLen, pathLen) == "\\" then
		 path = path:sub(1, pathLen - 1)
	end
	 
    local parts = { }
    for w in path:gmatch("[^\\]+") do
        if w == ".." and #parts ~=0 then table.remove(parts)
        elseif w ~= "."  then table.insert(parts, w)
        end
    end
    return table.concat(parts, "\\")
end

function ReloadScript.InitFileMap(RootPath)
	for _, rootpath in pairs(RootPath) do
		rootpath = Normalize(rootpath)
		local file = io.popen("dir /S/B /A:A \""..rootpath.."\"")
		io.input(file)
		for line in io.lines() do
	   		local FileName = string.match(line,".*\\(.*)%.lua")
	  	    if FileName ~= nil then
	            if ReloadScript.FileMap[FileName] == nil then
	            	ReloadScript.FileMap[FileName] = {}
	        	end
	        	local luapath = string.sub(line, #rootpath+2, #line-4)
				luapath = string.gsub(luapath, "\\", ".")
				ReloadScript.LuaPathToSysPath[luapath] = SysPath
	        	table.insert(ReloadScript.FileMap[FileName], {SysPath = line, LuaPath = luapath})
	    	end
	    end
	    file:close()
	end
end

function ReloadScript.InitFakeTable()
	local meta = {}
	ReloadScript.Meta = meta
	local function FakeT() return setmetatable({}, meta) end
	local function EmptyFunc() end
	local function pairs() return EmptyFunc end  
	local function setmetatable(t, metaT)
		ReloadScript.MetaMap[t] = metaT 
		return t
	end
	local function getmetatable(t, metaT)
		return setmetatable({}, t)
	end
	local function require(LuaPath)
		if not ReloadScript.RequireMap[LuaPath] then
			local FakeTable = FakeT()
			ReloadScript.RequireMap[LuaPath] = FakeTable
		end
		return ReloadScript.RequireMap[LuaPath]
	end
	function meta.__index(t, k)
		if k == "setmetatable" then
			return setmetatable
		elseif k == "pairs" or k == "ipairs" then
			return pairs
		elseif k == "next" then
			return EmptyFunc
		elseif k == "require" then
			return require
		else
			local FakeTable = FakeT()
			rawset(t, k, FakeTable)
			return FakeTable 
		end
	end
	function meta.__newindex(t, k, v) rawset(t, k, v) end
	function meta.__call() return FakeT(), FakeT(), FakeT() end
	function meta.__add() return meta.__call() end
	function meta.__sub() return meta.__call() end
	function meta.__mul() return meta.__call() end
	function meta.__div() return meta.__call() end
	function meta.__mod() return meta.__call() end
	function meta.__pow() return meta.__call() end
	function meta.__unm() return meta.__call() end
	function meta.__concat() return meta.__call() end
	function meta.__eq() return meta.__call() end
	function meta.__lt() return meta.__call() end
	function meta.__le() return meta.__call() end
	function meta.__len() return meta.__call() end
	return FakeT
end

function ReloadScript.InitProtection()
	ReloadScript.Protection = {}
	ReloadScript.Protection[setmetatable] = true
	ReloadScript.Protection[pairs] = true
	ReloadScript.Protection[ipairs] = true
	ReloadScript.Protection[next] = true
	ReloadScript.Protection[require] = true
	ReloadScript.Protection[ReloadScript] = true
	ReloadScript.Protection[ReloadScript.Meta] = true
	ReloadScript.Protection[math] = true
	ReloadScript.Protection[string] = true
	ReloadScript.Protection[table] = true
end

function ReloadScript.AddFileFromReloadScriptList()
	-- package.loaded[ReloadScript.UpdateListFile] = nil
	-- local FileList = require (ReloadScript.UpdateListFile)
	local FileList = ReloadScript.UpdateListFile
	ReloadScript.ALL = false
	ReloadScript.ReloadScriptMap = {}
	for _, file in pairs(FileList) do
		if file == "_ALL_" then
			ReloadScript.ALL = true
			for k, v in pairs(ReloadScript.FileMap) do
				for _, path in pairs(v) do
					if string.find(path.SysPath, "meta") == nil then
						ReloadScript.ReloadScriptMap[path.LuaPath] = path.SysPath  	
					end
				end
			end
			return
		end
		if ReloadScript.FileMap[file] then
			for _, path in pairs(ReloadScript.FileMap[file]) do
				if string.find(path.SysPath, "meta") == nil then
					ReloadScript.ReloadScriptMap[path.LuaPath] = path.SysPath  	
				end
			end
		else
			ReloadScript.FailNotify("HotUpdate can't not find "..file)
		end
	end
end

function ReloadScript.ErrorHandle(e)
	ReloadScript.FailNotify("HotUpdate Error\n"..tostring(e))
	ReloadScript.ErrorHappen = true
end

function ReloadScript.BuildNewCode(SysPath, LuaPath)
	io.input(SysPath)
	local NewCode = io.read("*all")
	if ReloadScript.ALL and ReloadScript.OldCode[SysPath] == nil then
		ReloadScript.OldCode[SysPath] = NewCode
		return
	end
	if ReloadScript.OldCode[SysPath] == NewCode then
		io.input():close()
		return false
	end
	ReloadScript.DebugNofity(SysPath)
	io.input(SysPath)  
	local cReloadScriptnk = "--[["..LuaPath.."]] "
	cReloadScriptnk = cReloadScriptnk..NewCode	
	io.input():close()
	local NewFunction = loadstring(cReloadScriptnk)
	if not NewFunction then 
  		ReloadScript.FailNotify(SysPath.." has syntax error.")  	
  		collectgarbage("collect")
  		return false
	else
		ReloadScript.FakeENV = ReloadScript.FakeT()
		ReloadScript.MetaMap = {}
		ReloadScript.RequireMap = {}
		setfenv(NewFunction, ReloadScript.FakeENV)
		local NewObject
		ReloadScript.ErrorHappen = false
		xpcall(function () NewObject = NewFunction() end, ReloadScript.ErrorHandle)
		if not ReloadScript.ErrorHappen then 
			ReloadScript.OldCode[SysPath] = NewCode
			return true, NewObject
		else
	  		collectgarbage("collect")
			return false
		end
	end
end

function ReloadScript.Travel_G()
	local visited = {}
	visited[ReloadScript] = true
	local function f(t)
		if (type(t) ~= "function" and type(t) ~= "table") or visited[t] or ReloadScript.Protection[t] then return end
		visited[t] = true
		if type(t) == "function" then
		  	for i = 1, math.huge do
				local name, value = debug.getupvalue(t, i)
				if not name then break end
				if type(value) == "function" then
					for _, funcs in ipairs(ReloadScript.ChangedFuncList) do
						if value == funcs[1] then
							debug.setupvalue(t, i, funcs[2])
						end
					end
				end
				f(value)
			end
		elseif type(t) == "table" then
			f(debug.getmetatable(t))
			local changeIndexs = {}
			for k,v in pairs(t) do
				f(k); f(v);
				if type(v) == "function" then
					for _, funcs in ipairs(ReloadScript.ChangedFuncList) do
						if v == funcs[1] then t[k] = funcs[2] end
					end
				end
				if type(k) == "function" then
					for index, funcs in ipairs(ReloadScript.ChangedFuncList) do
						if k == funcs[1] then changeIndexs[#changeIndexs+1] = index end
					end
				end
			end
			for _, index in ipairs(changeIndexs) do
				local funcs = ReloadScript.ChangedFuncList[index]
				t[funcs[2]] = t[funcs[1]] 
				t[funcs[1]] = nil
			end
		end
	end
	
	f(_G)
	local registryTable = debug.getregistry()
	f(registryTable)
	
	for _, funcs in ipairs(ReloadScript.ChangedFuncList) do
		if funcs[3] == "ReloadScriptDebug" then funcs[4]:ReloadScriptDebug() end
	end
end

function ReloadScript.ReplaceOld(OldObject, NewObject, LuaPath, From, Deepth)
	if type(OldObject) == type(NewObject) then
		if type(NewObject) == "table" then
			ReloadScript.UpdateAllFunction(OldObject, NewObject, LuaPath, From, "") 
		elseif type(NewObject) == "function" then
			ReloadScript.UpdateOneFunction(OldObject, NewObject, LuaPath, nil, From, "")
		end
	end
end

function ReloadScript.HotUpdateCode(LuaPath, SysPath)
	local OldObject = package.loaded[LuaPath]
	if OldObject ~= nil then
		ReloadScript.VisitedSig = {}
		ReloadScript.ChangedFuncList = {}
		local Success, NewObject = ReloadScript.BuildNewCode(SysPath, LuaPath)
		if Success then
			ReloadScript.ReplaceOld(OldObject, NewObject, LuaPath, "Main", "")
			for LuaPath, NewObject in pairs(ReloadScript.RequireMap) do
				local OldObject = package.loaded[LuaPath]
				ReloadScript.ReplaceOld(OldObject, NewObject, LuaPath, "Main_require", "")
			end
			setmetatable(ReloadScript.FakeENV, nil)
			ReloadScript.UpdateAllFunction(ReloadScript.ENV, ReloadScript.FakeENV, " ENV ", "Main", "")
			if #ReloadScript.ChangedFuncList > 0 then
				ReloadScript.Travel_G()
			end
			collectgarbage("collect")
		end
	elseif ReloadScript.OldCode[SysPath] == nil then 
		io.input(SysPath)
		ReloadScript.OldCode[SysPath] = io.read("*all")
		io.input():close()
	end
end

function ReloadScript.ResetENV(object, name, From, Deepth)
	local visited = {}
	local function f(object, name)
		if not object or visited[object] then return end
		visited[object] = true
		if type(object) == "function" then
			ReloadScript.DebugNofity(Deepth.."ReloadScript.ResetENV", name, "  from:"..From)
			xpcall(function () setfenv(object, ReloadScript.ENV) end, ReloadScript.FailNotify)
		elseif type(object) == "table" then
			ReloadScript.DebugNofity(Deepth.."ReloadScript.ResetENV", name, "  from:"..From)
			for k, v in pairs(object) do
				f(k, tostring(k).."__key", " ReloadScript.ResetENV ", Deepth.."    " )
				f(v, tostring(k), " ReloadScript.ResetENV ", Deepth.."    ")
			end
		end
	end
	f(object, name)
end

function ReloadScript.UpdateUpvalue(OldFunction, NewFunction, Name, From, Deepth)
	ReloadScript.DebugNofity(Deepth.."ReloadScript.UpdateUpvalue", Name, "  from:"..From)
	local OldUpvalueMap = {}
	local OldExistName = {}
	for i = 1, math.huge do
		local name, value = debug.getupvalue(OldFunction, i)
		if not name then break end
		OldUpvalueMap[name] = value
		OldExistName[name] = true
	end
	for i = 1, math.huge do
		local name, value = debug.getupvalue(NewFunction, i)
		if not name then break end
		if OldExistName[name] then
			local OldValue = OldUpvalueMap[name]
			if type(OldValue) ~= type(value) then
				debug.setupvalue(NewFunction, i, OldValue)
			elseif type(OldValue) == "function" then
				ReloadScript.UpdateOneFunction(OldValue, value, name, nil, "ReloadScript.UpdateUpvalue", Deepth.."    ")
			elseif type(OldValue) == "table" then
				ReloadScript.UpdateAllFunction(OldValue, value, name, "ReloadScript.UpdateUpvalue", Deepth.."    ")
				debug.setupvalue(NewFunction, i, OldValue)
			else
				debug.setupvalue(NewFunction, i, OldValue)
			end
		else
			ReloadScript.ResetENV(value, name, "ReloadScript.UpdateUpvalue", Deepth.."    ")
		end
	end
end 

function ReloadScript.UpdateOneFunction(OldObject, NewObject, FuncName, OldTable, From, Deepth)
	if ReloadScript.Protection[OldObject] or ReloadScript.Protection[NewObject] then return end
	if OldObject == NewObject then return end
	local signature = tostring(OldObject)..tostring(NewObject)
	if ReloadScript.VisitedSig[signature] then return end
	ReloadScript.VisitedSig[signature] = true
	ReloadScript.DebugNofity(Deepth.."ReloadScript.UpdateOneFunction "..FuncName.."  from:"..From)
	if pcall(debug.setfenv, NewObject, getfenv(OldObject)) then
		ReloadScript.UpdateUpvalue(OldObject, NewObject, FuncName, "ReloadScript.UpdateOneFunction", Deepth.."    ")
		ReloadScript.ChangedFuncList[#ReloadScript.ChangedFuncList + 1] = {OldObject, NewObject, FuncName, OldTable}
	end
end

function ReloadScript.UpdateAllFunction(OldTable, NewTable, Name, From, Deepth)
	if ReloadScript.Protection[OldTable] or ReloadScript.Protection[NewTable] then return end
	if OldTable == NewTable then return end
	local signature = tostring(OldTable)..tostring(NewTable)
	if ReloadScript.VisitedSig[signature] then return end
	ReloadScript.VisitedSig[signature] = true
	ReloadScript.DebugNofity(Deepth.."ReloadScript.UpdateAllFunction "..Name.."  from:"..From)
	for ElementName, Element in pairs(NewTable) do
		local OldElement = OldTable[ElementName]
		if type(Element) == type(OldElement) then
			if type(Element) == "function" then
				ReloadScript.UpdateOneFunction(OldElement, Element, ElementName, OldTable, "ReloadScript.UpdateAllFunction", Deepth.."    ")
			elseif type(Element) == "table" then
				ReloadScript.UpdateAllFunction(OldElement, Element, ElementName, "ReloadScript.UpdateAllFunction", Deepth.."    ")
			end
		elseif OldElement == nil and type(Element) == "function" then
			if pcall(setfenv, Element, ReloadScript.ENV) then
				OldTable[ElementName] = Element
			end
		end
	end
	local OldMeta = debug.getmetatable(OldTable)  
	local NewMeta = ReloadScript.MetaMap[NewTable]
	if type(OldMeta) == "table" and type(NewMeta) == "table" then
		ReloadScript.UpdateAllFunction(OldMeta, NewMeta, Name.."'s Meta", "ReloadScript.UpdateAllFunction", Deepth.."    ")
	end
end

function ReloadScript.Init(UpdateListFile, RootPath, FailNotify, ENV)
	ReloadScript.UpdateListFile = UpdateListFile
	ReloadScript.ReloadScriptMap = {}
	ReloadScript.FileMap = {}
	ReloadScript.NotifyFunc = FailNotify
	ReloadScript.OldCode = {}
	ReloadScript.ChangedFuncList = {}
	ReloadScript.VisitedSig = {}
	ReloadScript.FakeENV = nil
	ReloadScript.ENV = ENV or _G
	ReloadScript.LuaPathToSysPath = {}
	ReloadScript.InitFileMap(RootPath)
	ReloadScript.FakeT = ReloadScript.InitFakeTable()
	ReloadScript.InitProtection()
	ReloadScript.ALL = false
end

function ReloadScript.Update()
	ReloadScript.AddFileFromReloadScriptList()
	for LuaPath, SysPath in pairs(ReloadScript.ReloadScriptMap) do
		ReloadScript.HotUpdateCode(LuaPath, SysPath)
	end
end

ReloadScript.mUpdatef = nil

function ReloadScript.Run()
	if not UnityEngine.Application.isEditor then 
		return 
	end

	if ReloadScript.mUpdatef then
		UpdateBeat:Remove(ReloadScript.mUpdatef)
		ReloadScript.mUpdatef = nil
	end
	-- 初始化
	ReloadScript.Init(FileNameList, {ReloadScript.Lua})

	local curTime = os.time()
	--每帧更新
	ReloadScript.mUpdatef = function () 
		local nowTime = os.time()
		if nowTime - curTime > 1 then
			ReloadScript.Update() 
			curTime = nowTime
		end
	end
	UpdateBeat:Add(ReloadScript.mUpdatef)
end

return ReloadScript