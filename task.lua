-- vim: sw=3
local APKTOOL = '/storage/83BB-14E7/A2Lite/Archives/Program/jar/apktool_2.5.0.jar'
local JAVA    = 'java'
local PREFIX  = os.getenv('PREFIX')
local deps = {
    { 'apksogner', 'apksigner'},
    { 'zipalign', 'zipalign' },
}


local DIRS = {
   gen  = BASEDIR .. '/gen',
   orig = BASEDIR .. '/orig',
   adds = BASEDIR .. '/adds',
   orig_icon = BASEDIR .. '/orig/res/drawable-nodpi-v4',
   adds_icon = BASEDIR .. '/adds/res/drawable-nodpi',
   keystore  = '~/Documents/.restrict/.keystore',
}

local APKS = {
   orig = '~/storage/shared/apk/Whitepipe-Icon-Pack-1.0_old.apk',
   adds = '~/storage/shared/apk/Exported-Icon-Pack-1.0.apk',
}

local APPFILTERS = {
   orig = DIRS.orig .. '/assets/appfilter.xml',
   adds = DIRS.adds .. '/assets/appfilter.xml',
}

local function appfilter(file)
   local self = {
      start = '<?xml version="1.0" encoding="UTF-8"?><resources>',
      stop  = '</resources>',
      pairs = false,
      body  = false,
   }
   local f, err = io.open(file, 'r')
   if err then return nil, err end
   local text = f:read 'a'
   self.body  = text:match '<resources>(.*)</resources>'
   self.pairs = text:gmatch 'ComponentInfo{([^}]+)}" drawable="ic_([%d]+)"'
   return self
end




local function normalizenum(num)
   num = tostring(num)
   local l, z = num:len(), '0'
   if l == 1 then
      z = z:rep(3)
   elseif l == 2 then
      z = z:rep(2)
   elseif l == 4 then
      z = ''
   end
   return string.format('%s%s', z, num)
end


local ORIG_APPFILTER, err = appfilter(APPFILTERS.orig)
if err then print(err) end
local task = {}

function task:prepare()
   tag('info', 'Prepare')
   sh( 'mkdir -p %s/assets', DIRS.gen )
   sh( 'mkdir -p %s/res/values-nodpi-v4', DIRS.gen )
   sh( 'rm -fr %s/*.apk', DIRS.gen)
end


function task:decodeOrig()
   sh('%s -jar %s d -o %s %s', JAVA, APKTOOL, DIRS.orig, APKS.orig)
end
function task:decodeAdds()
   sh('%s -jar %s d -o %s %s', JAVA, APKTOOL, DIRS.adds, APKS.adds)
end

function task:decode()
   depends(self, 'decodeOrig', 'decodeAdds')
end



local DIFF_ITEM = ""
local ICON_NUM 
function task:patchIcons()
   depends(self, 'decodeOrig')

   local function copy_icon(adds_ic, orig_ic)
      local src = DIRS.adds_icon .. '/ic_' .. adds_ic .. '.png'
      local dst = DIRS.orig_icon .. '/ic_' .. orig_ic .. '.png'
      sh('cp %s %s', src, dst)
   end
   local num = 0
   local icons = {}
   for cmp, ic in ORIG_APPFILTER.pairs do
      num = num + 1
      icons[ cmp ] = ic
   end
   --print(num)
   local i = num
   local item = '<item component="ComponentInfo{%s}" drawable="ic_%s"/>\n'
   local adds = appfilter(APPFILTERS.adds)
   for cmp, icnum in adds.pairs do
      if not icons[ cmp ] then
	 i = i + 1
	 local ic = normalizenum(i)
	 copy_icon(icnum, ic)
	 DIFF_ITEM = DIFF_ITEM .. item:format(cmp, ic)
      end
   end

   ICON_NUM = i
end

function task:patchAppfilter()
   depends(self, 'patchIcons')
   local orig = ORIG_APPFILTER
   local out = DIRS.gen .. '/assets/appfilter.xml'
   os.remove(out)
   local f = io.open(out, 'w+')

   local text = string.format('%s%s%s%s', orig.start, orig.body, DIFF_ITEM, orig.stop)
   f:write(text)
   f:close()
   local orig  = DIRS.orig .. '/assets/appfilter.xml'
   local patch = DIRS.gen  .. '/assets/appfilter.patch'
   sh('diff -u %s %s > %s', orig, out, patch)
   sh('patch %s %s', orig, patch)
end


function task:patchDrawable()
   depends(self, 'patchIcons')
   local text = [[<?xml version="1.0" encoding="UTF-8"?><resources>


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


]]

   local fmt = '<item drawable="ic_%s" />'
   local add = {}
   for i=1, ICON_NUM do
      add[i] = fmt:format(normalizenum(i))
   end

   text = text .. table.concat(add, '\n') .. '\n</resources>'
   local out = DIRS.gen .. '/assets/drawable.xml'
   os.remove(out)
   local f = io.open(out, 'w+')
   if not f then return end
   f:write(text)
   f:close()

   local patch = DIRS.gen  .. '/assets/drawable.patch'
   local orig  = DIRS.orig .. '/assets/drawable.xml'
   sh('diff -u %s %s > %s', orig, out, patch )
   sh('patch %s %s', orig, patch)
   
end

function task:patchDrawables()
   depends(self, 'patchIcons')

   local text = [[<?xml version="1.0" encoding="utf-8"?>
<resources>
    <item type="drawable" name="ic_add_white_24dp">false</item>
]] 
   
   local fmt = '    <item type="drawable" name="ic_%s">false</item>'
   local adds = {}
   for i=ICON_NUM + 1, 3000 do
      adds[#adds + 1] = fmt:format(normalizenum(i))
   end
   local text = text .. table.concat(adds, '\n')
   text = text .. '\n    <item type="drawable" name="template">false</item>\n</resources>'

   local out = DIRS.gen .. '/res/values-nodpi-v4/drawables.xml'
   local orig = DIRS.orig .. '/res/values-nodpi-v4/drawables.xml'
   local patch = DIRS.gen .. '/res/values-nodpi-v4/drawables.patch'

   os.remove(out)
   local f, err = io.open(out, 'w+')
   if err then
      print(err)
      return
   end
   f:write(text)
   f:close()
   
   sh('diff -u %s %s > %s', orig, out, patch )
   sh('patch %s %s', orig, patch)
end


function task:build()
   depends(self, 'decode')
   tag('info', 'Building apk')
   local out = DIRS.gen .. '/unaligned.apk'
   sh("%s -jar %s b --use-aapt2 -a %s -o %s orig", JAVA, APKTOOL, PREFIX .. '/bin/aapt2', out)
end

function task:aligned()
   
   tag('info', 'aligning apk')
   sh('zipalign 4 %s %s', DIRS.gen .. '/unaligned.apk', DIRS.gen .. '/unsigned.apk')
end

function task:signing()
   tag('info', 'singing apk')
   sh('apksigner sign -in %s -out %s -key %s -cert %s',
      DIRS.gen .. '/unsigned.apk',
      DIRS.gen .. '/WhitePipeIconPack.apk',
      DIRS.keystore .. '/key.pk8',
      DIRS.keystore .. '/cert.x509.pem')
end

function task:all()
   depends(self, 'prepare', 'decode', 'patchIcons', 'patchAppfilter', 'patchDrawable', 'patchDrawables', 'build', 'aligned', 'signing')
end


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


return task
