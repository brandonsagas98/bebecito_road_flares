RoadFlares = RoadFlares or {}

RoadFlares.Constants = {
    ResourceName = 'bebecito_road_flares',
    ResourceMarker = 'bebecito_road_flares',
    DebugTag = '[BebecitoRoadFlares]',
    States = {
        IDLE = 'IDLE',
        AUTHORIZING = 'AUTHORIZING',
        EQUIPPING = 'EQUIPPING',
        EQUIPPED_UNLIT = 'EQUIPPED_UNLIT',
        IGNITING = 'IGNITING',
        DEPLOYMENT_READY = 'DEPLOYMENT_READY',
        PLACING = 'PLACING',
        COMMITTING = 'COMMITTING',
        STOPPING = 'STOPPING',
        Idle = 'idle',
        Active = 'active',
        Ending = 'ending'
    },
    Commands = {
        Activation = (Config and Config.Activation and Config.Activation.Command and Config.Activation.Command.Name) or 'bengalas',
        InternalActivationToggle = '+bebecito_road_flares_toggle',
        InternalActivationToggleRelease = '-bebecito_road_flares_toggle',
        StatAlias = 'flaresstatus',
        ClearAlias = 'flaresclear'
    },
    Events = {
        Client = {
            Notify = 'bebecito_road_flares:client:notify',
            AuthorizationResponse = 'bebecito_road_flares:client:authorizationResponse',
            StateUpdate = 'bebecito_road_flares:client:state',
            PlaceFlareResult = 'bebecito_road_flares:client:placeFlareResult',
            FlareSnapshot = 'bebecito_road_flares:client:flareSnapshot',
            FlareRemoved = 'bebecito_road_flares:client:flareRemoved',
            FlareUpdated = 'bebecito_road_flares:client:flareUpdated',
            IgnitionResult = 'bebecito_road_flares:client:ignitionResult',
            ActiveCountUpdated = 'bebecito_road_flares:client:activeCountUpdated',
            ManualExtinguishResult = 'bebecito_road_flares:client:manualExtinguishResult'
        },
        Server = {
            RequestIgnition = 'bebecito_road_flares:server:requestIgnition',
            RequestActivation = 'bebecito_road_flares:server:requestActivation',
            RequestPlaceFlare = 'bebecito_road_flares:server:requestPlaceFlare',
            RequestFlareSnapshot = 'bebecito_road_flares:server:requestFlareSnapshot',
            RequestManualExtinguish = 'bebecito_road_flares:server:requestManualExtinguish'
        }
    },
    SnapshotReasons = {
        Initial = 'initial',
        BucketChanged = 'bucket_changed',
        ManualRequest = 'manual_request'
    },
    Inputs = {
        Interact = 38,
        Confirm = 38,
        PrimaryAction = 24
    }
}
