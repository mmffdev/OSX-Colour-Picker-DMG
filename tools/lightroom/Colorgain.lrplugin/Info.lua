return {
    LrSdkVersion = 6.0,
    LrSdkMinimumVersion = 6.0,
    LrToolkitIdentifier = 'com.colorgain.lightroom.metadata',
    LrPluginName = 'Colorgain Metadata',
    VERSION = { major = 0, minor = 1, revision = 0, build = 1 },
    LrMetadataProvider = 'Metadata.lua',
    LrMetadataTagsetFactory = 'Tagset.lua',
    LrLibraryMenuItems = {
        { title = 'Refresh Colorgain Metadata', file = 'Refresh.lua' },
    },
}
