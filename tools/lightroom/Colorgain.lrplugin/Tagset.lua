-- Native Lightroom layout: selected file, readable custom fields, then provenance.
local prefix = 'com.colorgain.lightroom.metadata.'
return {
    id = 'colorgain', title = 'Colorgain',
    items = {
        'com.adobe.filename',
        'com.adobe.separator',
        { 'com.adobe.label', label='Colorgain Metadata' },
        prefix..'value', prefix..'application', prefix..'testId',
        { prefix..'note', height_in_lines=3 },
        'com.adobe.separator',
        { 'com.adobe.label', label='File Snapshot: Refresh To Update' },
        prefix..'status', prefix..'refreshed', prefix..'storage',
        { prefix..'source', height_in_lines=3 },
        { prefix..'error', height_in_lines=3 },
        'com.adobe.separator',
        { prefix..'fields', height_in_lines=6 },
    },
}
