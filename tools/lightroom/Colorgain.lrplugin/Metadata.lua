-- Extend Lightroom's native panel. All fields are read-only snapshots from disk.
local fields = {
    { 'status', 'Read Status' },
    { 'refreshed', 'Last Checked' },
    { 'value', 'Custom Value' },
    { 'application', 'Application' },
    { 'testId', 'Test ID' },
    { 'note', 'Test Note' },
    { 'storage', 'Storage' },
    { 'source', 'Source File' },
    { 'fields', 'All Colorgain Fields' },
    { 'error', 'Read Error' },
}
local definitions = {}
for _, field in ipairs(fields) do
    definitions[#definitions+1] = { id=field[1], title=field[2], dataType='string', readOnly=true }
end
return { schemaVersion=1, metadataFieldsForPhotos=definitions }
