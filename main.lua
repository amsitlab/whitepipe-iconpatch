-- vim: sw=3


local APKTOOL = '/storage/83BB-14E7/A2Lite/Archives/Program/jar/apktool_2.5.0.jar'
local JAVA    = 'java'
local VERSION_NAME = '1.0'



function exec(cmd, ...)
   local arg = { ... }
   if #arg > 0 then
      cmd = cmd:format(...)
   end

   local r = { os.execute(cmd) }
   if #r > 1 then
      return r[3]
   else
      return r[1] / 256
   end
end




local function isdir(d)
   return exec('test -d %s', d) == 0
end

local function decode(apk, dir)
   return exec('%s -jar %s d -out %s %s', JAVA, APKTOOL, dir, apk)
end





local function appfilter(dir, diffs)
   local file = dir .. '/assets/appfilter.xml'
   local f = io.open(file)
   if not f then return {} end
   local contents = f:read '*a'
   local res = {}
   local num = 0
   local add_num = 0
   local pattern = 'ComponentInfo{([^}]+)}"%s+drawable="([^"]+)"'
   for cmp, ico in contents:gmatch(pattern) do
      num = num + 1
      if diffs then
	 if not diffs[cmp] then
	    res[cmp] = ico
	    add_num = add_num + 1
	 end
      else
         res[cmp] = ico
      end
   end
   return res, num, add_num
end


local function normalizenumber(num)
   local l = num:len()
   local z = '0'
   if l == 2 then
      z = z:rep(2)
   elseif l == 1 then
      z = z:rep(3)
   elseif l == 4 then
      z = ''
   end
   return string.format('ic_%s%s', z, num)
end



local function patch(num, add_num, diffs, dirs)
   exec 'mkdir -p ./gen/assets'
   exec 'mkdir -p ./gen/res/values-nodpi-v4'


   local function diff(old, new, out)
      return exec('diff -u ' .. old .. ' ' .. new .. ' > ' .. out)
   end


   local function makepatch_appfilter(file, adds)
      local f    = io.open(file, 'r')
      local text = f:read '*a'
      f:close()
      local text_item = text:match('<resources>(.*)</resources>')
      for k, v in ipairs(adds) do
	 text_item = text_item .. v
      end

      exec 'rm -fr ./gen/assets/appfilter.xml'
      f = io.open('./gen/assets/appfilter.xml', 'w+')
      f:write(string.format('<resources>%s</resources>', text_item))
      f:close()

   end

   local function makepatch_drawable(num)
      local text_item = ''
      local item = '<item drawable="%s"/>\n'
      for i=1, num do
	 text_item = text_item .. item:format(normalizenumber(tostring(i)))
      end
      local text = [[<?xml encoding="UTF-8" version="1.0"?>\n<resources>


    <!--<item component=":LAUNCHER_ACTION_APP_DRAWER" drawable="ic_allapps" />-->
    <!--<item component=":BROWSER" drawable="browser3" />-->
    <!--<item component=":SMS" drawable="smss" />-->
    <!--<item component=":CALCULATOR" drawable="calculatorl" />-->
    <!--<item component=":CALENDAR" drawable="calendar" />-->
    <!--<item component=":CAMERA" drawable="google_camera" />-->
    <!--<item component=":CLOCK" drawable="clockl" />-->
    <!--<item-->
    <!--component=":CONTACTS"-->
    <!--drawable="contactsn" />-->
    <!--<item component=":EMAIL" drawable="emaillol" />-->
    <!--<item component=":GALLERY" drawable="galleryl" />-->
    <!--<item component=":PHONE" drawable="phone" />-->


]] .. text_item .. '</resources>'
      local file = './gen/assets/drawable.xml'
      exec('rm -fr ' .. file)
      local f = io.open(file, 'w+')
      f:write(text)
      f:close()
   end





   local function makepatch_drawables(file, num)
      local item = '    <item type="drawable" name="%s">false</item>\n'
      local text_item = ''
      for i=num+1, 3000 do
	 text_item = text_item .. item:format(normalizenumber(tostring(i)))
      end
      local newfile = './gen/res/values-nodpi-v4/drawables.xml'
      os.remove(newfile)
      local f = io.open(newfile, 'w+')
      local text = [[<?xml version="1.0" encoding="utf-8"?>
<resources>
    <item type="drawable" name="ic_add_white_24dp">false</item>
]] .. text_item .. '    <item type="drawable" name="template">false</item>\n</resources>'

     f:write(text)
     f:close()
   end


   local function makepatch_apktool_yml(file)
      local f = io.open(file, 'r')
      local text = f:read '*a'
      local versionName = text:match(".-versionName: '([^']+)'")
      local versionCode = versionName:match('([%d]+)')
      local vername = tonumber(versionName)
      versionName = tostring(vername + 0.1)
      VERSION_NAME = versionName

      text = text:gsub("versionName: '([^']+)'", "versionName: '"..versionName.."'")
      text = text:gsub("versionCode: '([^']+)'", "versionCode: '"..versionCode.."'")
      local newfile = './gen/apktool.yml'
      os.remove(newfile)
      local f = io.open(newfile, 'w+')
      f:write(text)
      f:close()
   end


   local i = num
   local item = '<item component="ComponentInfo{%s}" drawable="%s"/>\n'
   local items = {}
   for k, v in pairs(diffs) do
      i = i + 1
      local x = normalizenumber(tostring(i))
      items[#items + 1] = item:format(k,x)
      local src = string.format('%s/%s.png', dirs.adds_icondir, v)
      local dst = string.format('%s/%s.png', dirs.orig_icondir, x)
      local f, err = io.open(dst, 'r')
      if err then
	 exec('cp ' .. src .. ' ' .. dst)
      end
--[[
      print(k,
         string.format('%s/%s', dirs.adds_icondir, v),
	 string.format('%s/%s', dirs.orig_icondir, normalizenumber(tostring(i)))
     )
--]]

   end
   makepatch_appfilter(dirs.origdir .. '/assets/appfilter.xml', items)
   makepatch_drawable(num + add_num)
   makepatch_drawables(dirs.origdir .. '/res/values-nodpi/drawables.xml' ,num + add_num)
   makepatch_apktool_yml(dirs.origdir .. '/apktool.yml')

   diff( dirs.origdir .. '/assets/appfilter.xml', './gen/assets/appfilter.xml', './gen/assets/appfilter.patch')
   diff( dirs.origdir .. '/assets/drawable.xml', './gen/assets/drawable.xml', './gen/assets/drawable.patch')
   diff( dirs.origdir .. '/res/values-nodpi-v4/drawables.xml', './gen/res/values-nodpi-v4/drawables.xml', './gen/res/values-nodpi-v4/drawables.patch')
   diff( dirs.origdir .. '/apktool.yml', './gen/apktool.yml', './gen/apktool.patch')

   exec( 'patch ' .. dirs.origdir .. '/assets/appfilter.xml ./gen/assets/appfilter.patch') 
   exec( 'patch ' .. dirs.origdir .. '/assets/drawable.xml ./gen/assets/drawable.patch') 
   exec( 'patch ' .. dirs.origdir .. '/res/values-nodpi-v4/drawables.xml ./gen/res/values-nodpi-v4/drawables.patch') 
   exec( 'patch ' .. dirs.origdir .. '/apktool.yml ./gen/apktool.patch')

   exec 'rm -fr .gen/WhitePipeIconPack*'

   local apk_fmt_name = './gen/WhitePipeIconPack-' .. VERSION_NAME .. '%s.apk'
   local unaligned    = apk_fmt_name:format('_unaligned')
   local unsigned     = apk_fmt_name:format('_unsigned')
   local signed       = apk_fmt_name:format('')
   local key          = '~/Documents/.restrict/.keystore/key.pk8'
   local cert         = '~/Documents/.restrict/.keystore/cert.x509.pem'


   exec('java -jar %s b -a /data/data/com.termux/files/usr/bin/aapt -o %s orig', APKTOOL, unaligned)
   exec('zipalign 4 %s %s', unaligned, unsigned)
   exec('apksigner sign -in %s -out %s -key %s -cert %s', unsigned, signed, key, cert)
   os.remove(unaligned)
   os.remove(unsigned)
end




function main(arg)
   local origdir = './orig'
   local addsdir = './adds'
   local usage = string.format('usage: %s [old] [new]', arg[0])
   if #arg < 1 then
      print(usage)
      os.exit(1)
   end
   if not isdir(origdir) then
      decode(arg[1], origdir)
   end
   decode(arg[2], addsdir)
   local orig_appfilter, num = appfilter(origdir)
   local adds_appfilter, _, add_num = appfilter(addsdir, orig_appfilter)
   local orig_icondir = string.format('%s/res/drawable-nodpi-v4', origdir)
   local adds_icondir = string.format('%s/res/drawable-nodpi', addsdir)

   patch(num, add_num, adds_appfilter, {
      origdir = origdir,
      addsdir = addsdir,
      orig_icondir = orig_icondir,
      adds_icondir = adds_icondir
   })
end



main(arg)
