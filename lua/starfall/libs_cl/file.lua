local checkluatype = SF.CheckLuaType
local registerprivilege = SF.Permissions.registerPrivilege

-- Register privileges
registerprivilege("file.read", "Read files", "Allows the user to read files from data/sf_filedata directory", { client = { default = 1 } })
registerprivilege("file.write", "Write files", "Allows the user to write files to data/sf_filedata directory", { client = { default = 1 } })
registerprivilege("file.writeTemp", "Write temporary files", "Allows the user to write temp files to data/sf_filedatatemp directory", { client = { default = 1 } })
registerprivilege("file.exists", "File existence check", "Allows the user to determine whether a file in data/sf_filedata exists", { client = { default = 1 } })
registerprivilege("file.find", "File find", "Allows the user to see what files are in data/sf_filedata", { client = { default = 1 } })
registerprivilege("file.findInGame", "File find in garrysmod", "Allows the user to see what files are in garrysmod", { client = { default = 1 } })
registerprivilege("file.open", "Get a file object", "Allows the user to use a file object", { client = { default = 1 } })

file.CreateDir("sf_filedata/")
file.CreateDir("sf_filedatatemp/")

local cv_temp_maxfiles = CreateConVar("sf_file_tempmax", "256", { FCVAR_ARCHIVE }, "The max number of files a player can store")
local cv_temp_maxusersize = CreateConVar("sf_file_tempmaxusersize", "64", { FCVAR_ARCHIVE }, "The max total of megabytes a player can store")
local cv_temp_maxsize = CreateConVar("sf_file_tempmaxsize", "128", { FCVAR_ARCHIVE }, "The max total of megabytes allowed in cache")

--- File functions. Allows modification of files.
-- @name file
-- @class library
-- @libtbl file_library
SF.RegisterLibrary("file")

--- File type
-- @name File
-- @class type
-- @libtbl file_methods
SF.RegisterType("File", true, false)


-- Temp file cache class
local TempFileCache = {}
do
	function TempFileCache:Initialize()
		local entries = {}
		local files, dirs = file.Find("sf_filedatatemp/*", "DATA")
		for k, plyid in ipairs(dirs) do
			local dir = "sf_filedatatemp/"..plyid
			files = file.Find(dir.."/*", "DATA")
			if next(files)==nil then SF.DeleteFolder(dir) else
				for k, filen in ipairs(files) do
					local path = dir.."/"..filen
					local time, size = file.Time(path, "DATA"), file.Size(path, "DATA")
					entries[path] = {path = path, plyid = plyid, time = time, size = size}
				end
			end
		end
		self.entries = entries
	end

	function TempFileCache:Write(plyid, filename, data)
		local dir = "sf_filedatatemp/"..plyid
		local path = dir.."/"..filename
		local ok, reason = self:CheckSize(plyid, path, #data)
		if ok then
			if self.entries[path] then
				file.Delete(path)
				if file.Exists(path, "DATA") then SF.Throw("The existing file is currently locked!", 3) end
			end
			self.entries[path] = {path = path, plyid = plyid, time = os.time(), size = #data}
			file.CreateDir(dir)
			print("[SF] Writing temp file: " .. path)
			local f = file.Open(path, "wb", "DATA")
			if not f then SF.Throw("Couldn't open file for writing!", 3) end
			f:Write(data)
			f:Close()
			return "data/"..path
		else
			SF.Throw(reason, 3)
		end
	end

	function TempFileCache:CheckSize(plyid, path, size)
		local plyentries = {}
		local plysize = size
		local plycount = 1
		local totalsize = size
		for k, v in pairs(self.entries) do
			if k~=path then
				if v.plyid == plyid then
					plycount = plycount + 1
					plysize = plysize + v.size
					plyentries[#plyentries+1] = v
				end
				totalsize = totalsize + v.size
			end
		end

		local check = {plyentries = plyentries, plysize = plysize, plycount = plycount, totalsize = totalsize}
		if check.plycount >= cv_temp_maxfiles:GetInt() then
			self:CleanPly(check)
			if check.plycount >= cv_temp_maxfiles:GetInt() then
				return false, "Reached the file count limit!"
			end
		end
		if check.plysize >= cv_temp_maxusersize:GetFloat()*1e6 then
			self:CleanPly(check)
			if check.plysize >= cv_temp_maxusersize:GetFloat()*1e6 then
				return false, "Your temp file folder is full!"
			end
		end
		if check.totalsize >= cv_temp_maxsize:GetFloat()*1e6 then
			self:Clean(check)
			if check.totalsize >= cv_temp_maxsize:GetFloat()*1e6 then
				return false, "The temp file cache has reached its limit!"
			end
		end
		return true
	end

	-- Clean based on the file count and per player size limit
	function TempFileCache:CleanPly(check)
		-- Sort by time
		table.sort(check.plyentries, function(a,b) return a.time>b.time end)

		while (check.plycount >= cv_temp_maxfiles:GetInt() or check.plysize >= cv_temp_maxusersize:GetFloat()*1e6) and #check.plyentries>0 do
			local entry = table.remove(check.plyentries)
			file.Delete(entry.path)
			if not file.Exists(entry.path, "DATA") then
				check.plysize = check.plysize - entry.size
				check.plycount = check.plycount - 1
				self.entries[entry.path] = nil
			end
		end
	end

	-- Clean based on the total size limit
	function TempFileCache:CleanAll(check)
		-- First sort by players not connected
		local connectedplys = {}
		local disconnectedplys = {}
		for path, v in pairs(self.entries) do
			if player.GetBySteamID64(v.plyid) then
				connectedplys[#connectedplys+1] = v
			else
				disconnectedplys[#disconnectedplys+1] = v
			end
		end
		-- Sort by time
		table.sort(connectedplys, function(a,b) return a.time>b.time end)
		table.sort(disconnectedplys, function(a,b) return a.time>b.time end)
		local sorted = table.Add(connectedplys, disconnectedplys)

		while check.totalsize >= cv_temp_maxsize:GetFloat()*1e6 and #sorted>0 do
			local entry = table.remove(sorted)
			file.Delete(entry.path)
			if not file.Exists(entry.path, "DATA") then
				check.totalsize = check.totalsize - entry.size
				self.entries[entry.path] = nil
			end
		end
	end

	TempFileCache:Initialize()
end


return function(instance)
local checkpermission = instance.player ~= SF.Superuser and SF.Permissions.check or function() end

-- Register functions to be called when the chip is initialised and deinitialised
instance:AddHook("initialize", function()
	instance.data.files = {}
	instance.data.tempfilewrites = 0
end)

instance:AddHook("deinitialize", function()
	for file, _ in pairs(instance.data.files) do
		file:Close()
	end
end)


local file_library = instance.Libraries.file
local file_methods, file_meta, wrap, unwrap = instance.Types.File.Methods, instance.Types.File, instance.Types.File.Wrap, instance.Types.File.Unwrap


--- Opens and returns a file
-- @param path Filepath relative to data/sf_filedata/.
-- @param mode The file mode to use. See lua manual for explaination
-- @return File object or nil if it failed
function file_library.open(path, mode)
	checkpermission (instance, path, "file.open")
	checkluatype (path, TYPE_STRING)
	checkluatype (mode, TYPE_STRING)
	local f = file.Open("sf_filedata/" .. SF.NormalizePath(path), mode, "DATA")
	if f then
		instance.data.files[f] = true
		return wrap(f)
	end
end

--- Reads a file from path
-- @param path Filepath relative to data/sf_filedata/.
-- @return Contents, or nil if error
function file_library.read(path)
	checkpermission (instance, path, "file.read")
	checkluatype (path, TYPE_STRING)
	return file.Read("sf_filedata/" .. SF.NormalizePath(path), "DATA")
end


local allowedExtensions = {["txt"] = true,["jpg"] = true,["png"] = true,["vtf"] = true,["dat"] = true,["json"] = true,["vmt"] = true}
local function checkExtension(filename)
	if not allowedExtensions[string.GetExtensionFromFilename(filename)] then SF.Throw("File name must end with .txt, .jpg, .png, .vtf, .json, .vmt, or .dat extension!", 3) end
end

--- Writes to a file
-- @param path Filepath relative to data/sf_filedata/.
-- @param data The data to write
-- @return True if OK, nil if error
function file_library.write(path, data)
	checkpermission (instance, path, "file.write")
	checkluatype (path, TYPE_STRING)
	checkluatype (data, TYPE_STRING)

	checkExtension(path)

	local f = file.Open("sf_filedata/" .. SF.NormalizePath(path), "wb", "DATA")
	if not f then SF.Throw("Couldn't open file for writing.", 2) return end
	f:Write(data)
	f:Close()
end

--- Writes a temporary file. Throws an error if it is unable to.
-- @param filename The name to give the file. Must be only a file and not a path
-- @param data The data to write
-- @return The generated path for your temp file
function file_library.writeTemp(filename, data)
	checkluatype(filename, TYPE_STRING)
	checkluatype(data, TYPE_STRING)

	checkpermission (instance, nil, "file.writeTemp")
	if instance.data.tempfilewrites >= cv_temp_maxfiles:GetInt() then SF.Throw("Exceeded max number of files allowed to write!", 2) end

	if #filename > 128 then SF.Throw("Filename is too long!", 2) end
	checkExtension(filename)
	filename = string.lower(string.GetFileFromFilename(filename))

	local path = TempFileCache:Write(instance.player:SteamID64(), filename, data)
	instance.data.tempfilewrites = instance.data.tempfilewrites + 1
	return path
end

--- Returns the path of a temp file if it exists. Otherwise returns nil
-- @param filename The temp file name. Must be only a file and not a path
-- @return The path to the temp file or nil if it doesn't exist
function file_library.existsTemp(filename)
	checkluatype(filename, TYPE_STRING)

	if #filename > 128 then SF.Throw("Filename is too long!", 2) end
	checkExtension(filename)
	filename = string.lower(string.GetFileFromFilename(filename))

	local path = "sf_filedatatemp/"..instance.player:SteamID64().."/"..filename
	if file.Exists(path, "DATA") then
		return "data/"..path
	end
end

--- Appends a string to the end of a file
-- @param path Filepath relative to data/sf_filedata/.
-- @param data String that will be appended to the file.
function file_library.append(path, data)
	checkpermission (instance, path, "file.write")
	checkluatype (path, TYPE_STRING)
	checkluatype (data, TYPE_STRING)

	local f = file.Open("sf_filedata/" .. SF.NormalizePath(path), "ab", "DATA")
	if not f then SF.Throw("Couldn't open file for writing.", 2) return end
	f:Write(data)
	f:Close()
end

--- Checks if a file exists
-- @param path Filepath relative to data/sf_filedata/.
-- @return True if exists, false if not, nil if error
function file_library.exists(path)
	checkpermission (instance, path, "file.exists")
	checkluatype (path, TYPE_STRING)
	return file.Exists("sf_filedata/" .. SF.NormalizePath(path), "DATA")
end

--- Deletes a file
-- @param path Filepath relative to data/sf_filedata/.
-- @return True if successful, nil if it wasn't found
function file_library.delete(path)
	checkpermission (instance, path, "file.write")
	checkluatype (path, TYPE_STRING)
	path = "sf_filedata/" .. SF.NormalizePath(path)
	if file.Exists(path, "DATA") then
		file.Delete(path)
		return true
	end
end

--- Creates a directory
-- @param path Filepath relative to data/sf_filedata/.
function file_library.createDir(path)
	checkpermission (instance, path, "file.write")
	checkluatype (path, TYPE_STRING)
	file.CreateDir("sf_filedata/" .. SF.NormalizePath(path))
end

--- Enumerates a directory
-- @param path The folder to enumerate, relative to data/sf_filedata/.
-- @param sorting Optional sorting arguement. Either nameasc, namedesc, dateasc, datedesc
-- @return Table of file names
-- @return Table of directory names
function file_library.find(path, sorting)
	checkpermission (instance, path, "file.find")
	checkluatype (path, TYPE_STRING)
	if sorting~=nil then checkluatype (sorting, TYPE_STRING) end
	return file.Find("sf_filedata/" .. SF.NormalizePath(path), "DATA", sorting)
end

--- Enumerates a directory relative to gmod
-- @param path The folder to enumerate, relative to garrysmod.
-- @param sorting Optional sorting arguement. Either nameasc, namedesc, dateasc, datedesc
-- @return Table of file names
-- @return Table of directory names
function file_library.findInGame(path, sorting)
	checkpermission (instance, path, "file.findInGame")
	checkluatype (path, TYPE_STRING)
	if sorting~=nil then checkluatype (sorting, TYPE_STRING) end
	return file.Find(SF.NormalizePath(path), "GAME", sorting)
end

--- Wait until all changes to the file are complete
function file_methods:flush()
	unwrap(self):Flush()
end

--- Flushes and closes the file. The file must be opened again to use a new file object.
function file_methods:close()
	local f = unwrap(self)
	instance.data.files[f] = nil
	f:Close()
end

--- Sets the file position
-- @param n The position to set it to
function file_methods:seek(n)
	checkluatype (n, TYPE_NUMBER)
	unwrap(self):Seek(n)
end

--- Moves the file position relative to its current position
-- @param n How much to move the position
-- @return The resulting position
function file_methods:skip(n)
	checkluatype (n, TYPE_NUMBER)
	return unwrap(self):Skip(n)
end

--- Returns the current file position
-- @return The current file position
function file_methods:tell()
	return unwrap(self):Tell()
end

--- Returns the file's size in bytes
-- @return The file's size
function file_methods:size()
	return unwrap(self):Size()
end

--- Reads a certain length of the file's bytes
-- @param n The length to read
-- @return The data
function file_methods:read(n)
	return unwrap(self):Read(n)
end

--- Reads a boolean and advances the file position
-- @return The data
function file_methods:readBool()
	return unwrap(self):ReadBool()
end

--- Reads a byte and advances the file position
-- @return The data
function file_methods:readByte()
	return unwrap(self):ReadByte()
end

--- Reads a double and advances the file position
-- @return The data
function file_methods:readDouble()
	return unwrap(self):ReadDouble()
end

--- Reads a float and advances the file position
-- @return The data
function file_methods:readFloat()
	return unwrap(self):ReadFloat()
end

--- Reads a line and advances the file position
-- @return The data
function file_methods:readLine()
	return unwrap(self):ReadLine()
end

--- Reads a long and advances the file position
-- @return The data
function file_methods:readLong()
	return unwrap(self):ReadLong()
end

--- Reads a short and advances the file position
-- @return The data
function file_methods:readShort()
	return unwrap(self):ReadShort()
end

--- Writes a string to the file and advances the file position
-- @param str The data to write
function file_methods:write(str)
	checkluatype (str, TYPE_STRING)
	unwrap(self):Write(str)
end

--- Writes a boolean and advances the file position
-- @param x The boolean to write
function file_methods:writeBool(x)
	checkluatype (x, TYPE_BOOL)
	unwrap(self):WriteBool(x)
end

--- Writes a byte and advances the file position
-- @param x The byte to write
function file_methods:writeByte(x)
	checkluatype (x, TYPE_NUMBER)
	unwrap(self):WriteByte(x)
end

--- Writes a double and advances the file position
-- @param x The double to write
function file_methods:writeDouble(x)
	checkluatype (x, TYPE_NUMBER)
	unwrap(self):WriteDouble(x)
end

--- Writes a float and advances the file position
-- @param x The float to write
function file_methods:writeFloat(x)
	checkluatype (x, TYPE_NUMBER)
	unwrap(self):WriteFloat(x)
end

--- Writes a long and advances the file position
-- @param x The long to write
function file_methods:writeLong(x)
	checkluatype (x, TYPE_NUMBER)
	unwrap(self):WriteLong(x)
end

--- Writes a short and advances the file position
-- @param x The short to write
function file_methods:writeShort(x)
	checkluatype (x, TYPE_NUMBER)
	unwrap(self):WriteShort(x)
end

end
