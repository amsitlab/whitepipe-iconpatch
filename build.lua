#!/usr/bin/lua5.3
-- vim: sw=3
local fopen = assert( io.open )
local popen = assert( io.popen )
local iotype = assert( io.type )
local exit = assert( os.exit )
local getenv = assert( os.getenv )
local table = assert( table )

--[[
local deps = {
   { pkg = 'dx', cmd = 'dx', },
   { pkg = 'ecj', cmd = 'ecj', },
   { pkg = 'aapt', cmd = 'aapt', },
   { pkg = 'aapt', cmd = 'zipalign', },
   { pkg = 'apksigner', cmd = 'apksigner', },
   { pkg = 'openssl-tool', cmd = 'openssl', },
   { pkg = 'findutils', cmd = 'find' }
}
--]]

function tag(name, ...)
   print('['..name..']', ...)
end

options = {
   verbose = {
      val = false,
      print = function(self, name, ...)
         if self.val == true then
            tag(name, ...)
         end
      end
   },
   defines = {},
}

function sh(cmd, ...)
   local arg = { ... }
   if #arg > 0 then
      cmd = cmd:format(...)
   end
   local x = { os.execute(cmd) }
   if #x == 3 then
      return x[3]
   else
      return x[1] / 256
   end
end


function shell(args)
   local q = {}
   local type_args = type(args)
   if type_args == 'table' then
      q = args
   elseif type_args == 'string' then
      table.insert(q, args)
   end

   local cmd = table.concat(q, ' ')
   options.verbose:print('shell', cmd)
   local p = popen(cmd)
   local lines = {}
   for l in p:lines() do
      table.insert(lines, l)
   end
   local res = { p:close() }
   res.lines = lines
   res.success = res[1] or false
   res.context = res[2] or 'exit'
   res.code = res[3] or 127 -- exit code
   -- remove numberic index
   table.remove(res, 1) -- 1
   table.remove(res, 1) -- 2
   table.remove(res, 1) -- 3
   function res:exit_on_fail(...)
      if self.code > 0 then
         tag('error', ...)
         exit(self.code)
      end
   end
   return res
end
--[[
local function checking_dependencies(t)
   assert(type(t) == 'table')
   for k, v in pairs(t) do
      local r = shell { 'command', '-v', v.cmd }
      if r.code > 0 then
         local install = shell { "apt install", v.pkg }
         if install.code > 0 then
            exit(install.code)
         end
      end
   end
end
--]]
--[[
--------------- [ Project Variables ] ---------------
local APPNAME = 'WhitePipeIconPack'
local PREFIX  = getenv('PREFIX')
local JAVA    = PREFIX .. '/bin/java'
local APKTOOL = '~/storage/jar/extern/apktool_2.5.0.jar'

local dirs = {
   GEN  = './.gen',
   ORIG = './orig',
   ADDS = './adds',
}

local appfilters = {
   orig = dirs.ORIG .. '/assets/appfilter.xml',
   adds = dirs.ADDS .. '/assets/appfilter.xml',
}

local apkfiles = {
   UNSIGNED = 'unsigned.apk',
   ALIGNED = 'aligned.apk',
   SIGNED = 'signed.apk',
}

local KEYSTORE_DIR = '~/Documents/.restrict/.keystore'
local certs = {
   pk8  = KEYSTORE_DIR .. '/key.pk8',
   x509 = KEYSTORE_DIR .. '/cert.x509.pem',
}
--]]
local isAllowDepends = true
calleds = {}
function depends(task,...)
   if not isAllowDepends then return end

   for i=1, select('#', ...) do
      local funcname = select(i, ...)
      assert(type(funcname == 'string'))
      if calleds[ funcname ] ~= true then
	 calleds[ funcname ] = true
	 local ok, res = pcall(task[funcname], task)
      	 if not ok then
      	    print(res)
      	    exit(1)
      	 end
      end
   end
end
--[[
-------------------[ Task Deinitions ]----------------

local task = {}
function task:help()
   print('lua5.3 build.lua [options] [task]')
   print('options')
   print('', '-help')
   print('', '', 'show this message.')
   print('', '-list')
   print('', '', 'show available tasks')
   print('', '-verbose')
   print('', '', 'run task with verbose')
   exit(0)
end



function task:decode_orig()
   local apk = '~/storage/shared/apk/Whitepipe-Icon-Pack-1.0_old.apk'
   local x = sh('%s -jar %s d -o %s %s', JAVA, APKTOOL, dirs.ORIG, apk)
end

function task:decode_adds()
   local apk = '~/storage/shared/apk/Exported-Icon-Pack-1.0.apk'
   local x = sh('%s -jar %s d -o %s %s', JAVA, APKTOOL, dirs.ADDS, apk)
end

function task:decode()
   depends(self, 'decode_orig', 'decode_adds')
end

local ORIG_APPFILTER_ADD_ITEM = ""
function task:icondiff()
   function appfilter_items(filename)
      local function fget_contents(file)
         local f, err = io.open(file, 'r')
         if err then return false, err end
         local text = f:read '*a'
         f:close()
         return text
      end
      local item, err = fget_contents(filename)
      if err then 
	 print(err)
	 os.exit(1)
      end
      return item:gmatch 'ComponentInfo{([^}]+)}" drawable="ic_([%d]+)"'
   end

   local function createnum(num)
      num = tostring(num)
      local l = num:len()
      local z = '0'
      if l == 1 then
	 z = z:rep(3)
      elseif l == 2 then
	 z = z:rep(2)
      end
      return string.format('%s%s', z, num)
   end

   local function icnum2path(dir, icnum)
      return string.format("%s/ic_%s.png", dir, icnum)
   end

   local orig = {}
   local num  = 0
   for cmp, icnum in appfilter_items(appfilters.orig) do
      orig[cmp] = icnum
      num = num + 1
      --print(cmp, icnum2path(dirs.ORIG .. '/res/drawble-nodpi-v4', icnum))
   end

   local i = num
   local item = '<item component="ComponentInfo{%s}" drawable="ic_%s" /> : %s\n'

   for cmp, icnum in appfilter_items(appfilters.adds) do
      if not orig[ cmp ] then
	 i = i + 1
	 local ic = createnum(i)
	 ORIG_APPFILTER_ADD_ITEM = ORIG_APPFILTER_ADD_ITEM .. item:format(cmp, ic, icnum)
      end
   end

   print(ORIG_APPFILTER_ADD_ITEM)
end


function task:all()
   depends(self, 'decode_orig', 'decode_adds', 'icondiff')
end

--]]


--------------- [ Argument parsing ] --------------
BASEDIR = '.'
local task = {}
local function eat_options(arg)
   if arg == '-verbose' then
      options.verbose.val = true
   end
   if arg:sub(1, 2) == '-D' then
      local key_val = arg:sub(3)
      local key, val = key_val:match '([^=]+)=(.+)'
      options.defines[key] = val
   end
   if arg == '-list' then
      print('Available task:')
      for k, v in pairs(task) do
         if type(v) == 'function' then
            print('', k)
         end
      end
      exit(0)
   end
end

local function eat_task(arg)

   arg = arg or 'all'
   if not task[arg] then
      tag('error', 'Undefined task:', arg)
      return
   end
   local ok, result = pcall(task[arg], task)
   if not ok then
      tag('error', result)
   end
end

local function main(arg)
   BASEDIR = arg[0]:match('(.*/)build%.lua') or '.'
   local f = loadfile(BASEDIR .. '/task.lua')
   task = f()

   if #arg == 0 then
      eat_task('help')
   end
   local checking = false
   local i = 1
   while arg[i] and arg[i]:sub(1,1)=='-' do
         eat_options(arg[i])
         table.remove(arg, i)
         i = i + 1
   end
   if #arg == 0 then
      return
   end
   for i=1, #arg do
      --[[
      if false == checking then
         checking_dependencies(deps)
         checking = true
      end
      --]]
      eat_task(arg[i])
   end
end

main(arg)
