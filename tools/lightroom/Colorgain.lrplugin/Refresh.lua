local LrApplication = import 'LrApplication'
local LrDialogs = import 'LrDialogs'
local LrTasks = import 'LrTasks'
local LrPathUtils = import 'LrPathUtils'
local LrFileUtils = import 'LrFileUtils'
local LrUUID = import 'LrUUID'
local LrProgressScope = import 'LrProgressScope'
local keys = { 'status','refreshed','value','application','testId','note','storage','source','fields','error' }
local function quote(s) return "'" .. string.gsub(s, "'", "'\\''") .. "'" end
local function decode(s) return (s:gsub('%%(%x%x)',function(h) return string.char(tonumber(h,16)) end)) end

LrTasks.startAsyncTask(function()
    local catalog = LrApplication.activeCatalog()
    local photos = catalog:getTargetPhotos()
    if not catalog:getTargetPhoto() or #photos == 0 then
        LrDialogs.message('Colorgain Metadata','Select a photograph in the Library module first.','info')
        return
    end
    local helper = LrPathUtils.child(_PLUGIN.path,'ColorgainMetadataReader')
    if not LrFileUtils.exists(helper) then
        LrDialogs.message('Colorgain Metadata','The metadata reader is missing. Reinstall the complete Colorgain plug-in.','critical')
        return
    end
    local progress = LrProgressScope { title='Reading Colorgain metadata' }
    local temp = LrPathUtils.child(LrPathUtils.getStandardFilePath('temp'),'colorgain-'..LrUUID.generateUUID()..'.txt')
    local ok, failure = LrTasks.pcall(function()
        for i, photo in ipairs(photos) do
            if progress:isCanceled() then break end
            local path = photo:getRawMetadata('path')
            progress:setCaption(LrPathUtils.leafName(path))
            local result = {}
            local code = LrTasks.execute(quote(helper)..' '..quote(path)..' > '..quote(temp)..' 2>&1')
            local text = LrFileUtils.readFile(temp) or ''
            LrFileUtils.delete(temp)
            if code == 0 then
                for line in text:gmatch('[^\r\n]+') do
                    local k,v = line:match('^([%w]+)\t(.*)$')
                    if k then result[k]=decode(v) end
                end
            end
            if not result.status then
                result = { status='Could not refresh', error='The metadata reader did not complete. Check the plug-in installation and file access.' }
            end
            result.refreshed = os.date('%Y-%m-%d %H:%M:%S %Z')
            catalog:withWriteAccessDo('Refresh Colorgain Metadata',function()
                -- Clear previous values on errors or missing fields to prevent stale claims.
                for _, key in ipairs(keys) do photo:setPropertyForPlugin(_PLUGIN,key,result[key] or '') end
            end)
            progress:setPortionComplete(i,#photos)
        end
    end)
    LrFileUtils.delete(temp)
    progress:done()
    if not ok then LrDialogs.message('Colorgain Metadata','Refresh stopped: '..tostring(failure),'critical') end
end)
