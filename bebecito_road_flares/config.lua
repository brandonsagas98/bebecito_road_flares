Config = {}

Config.Debug = false
Config.Locale = 'es'

-- 0 disables quantity limits. Positive values opt into owner limits.
Config.MaxActiveFlaresPerPlayer = 0
Config.MaxActiveFlaresGlobal = 0
-- auto: OX first (including Qbox), then QB inventory, then native ESX.
-- custom: register a SERVER adapter; none: explicit inventory-free standalone.
Config.Inventory = { Provider = 'auto', ItemName = 'bd_road_flare', SessionMilliseconds = 300000 }
Config.FlareDurationMinutes = 15
Config.Realism = {
    ConsumeOnIgnition = true,
    GroundPitchDegrees = 80.0,
    GroundLiftMeters = 0.012,
    -- 0 keeps every nearby flare eligible; shared smoke/draw budgets still apply.
    MaximumDetailedFlames = 0,
    MaximumSmokeEmitters = 0,
    -- Share smoke detail under load while keeping each nearby signal represented.
    -- Shared crowd budget; one flare still uses its full 24-puff trail.
    MaximumSmokePuffs = 128,
    -- Environment-only boost; flame geometry, burn stages and emission budget stay unchanged.
    SmokeDensityMultiplier = 2.0,
    HaloAreaMultiplier = 2.0,
    DetailDistance = 35.0,
    GlowDistance = 250.0,
    SmokeDistance = 120.0,
    FullSmokeDistance = 8.0,
    Sparks = true,
    SpentLifetimeMilliseconds = 600000,
    MaximumSpentProps = 12
}
Config.BurnModels = {
    {name='bd_road_flare_ground_0',length=.220},
    {name='bd_road_flare_ground_1',length=.165},
    {name='bd_road_flare_ground_2',length=.110},
    {name='bd_road_flare_ground_3',length=.055}
}
Config.Lifecycle = {
    AutomaticExtinguishDurationMilliseconds = 3500,
    ParticleFade = {
        Enabled = true,
        MinimumAlpha = 0.0,
        MinimumScaleMultiplier = 0.35
    }
}

Config.ManualExtinguish = {
    Enabled = true,
    ServerMaximumDistance = 3.0,
    RequestRateLimitMilliseconds = 750,
    RequestTimeoutMilliseconds = 4000,
    ExtinguishDurationMilliseconds = 4000,
    FaceTargetDurationMilliseconds = 600,
    ProximityCheckMilliseconds = 200
}

-- Passive ribbon: event-driven, max 12 nearby flare nodes / 24 invisible pieces.
-- No driver tasks, vehicle pool scans or independent proximity worker.
Config.TrafficLite = { Enabled = true }
-- Native navigation closures follow the same active-flare lifecycle; no test TTL.
Config.NativeRoadClosure = { Enabled = true }
-- Tiny native collider; BD appearance stays attached, with no asset hot-reload.
-- Enable only after the embedded-collision BD asset package has been loaded.
Config.GroundPhysics = { Enabled = true, Mass = 0.2 }

Config.Activation = {
    Inventory = {
        Enabled = true,
        ItemName = 'bd_road_flare'
    },

    Command = {
        Enabled = true,
        Name = 'bengalas'
    },

    Keybind = {
        Enabled = true,
        DefaultKey = 'F6',
        Description = 'Sacar o guardar bengalas'
    },
}

Config.FlareProp = {
    Model = 'bd_road_flare',
    LitModel = 'bd_road_flare_lit',

    Hand = {
        Bone = 57005,

        Position = {
            x = 0.113,
            y = -0.055,
            z = -0.016
        },

        Rotation = {
            x = -90.0,
            y = 0.0,
            z = 0.0
        }
    },

    ModelLoadTimeoutMilliseconds = 5000
}

Config.FlareVisuals = {
    StopRampMilliseconds = 450,

    Light = {
        Enabled = true,

        Color = {
            r = 255,
            g = 14,
            b = 5
        },

        Range = 10.0,
        Intensity = 6.0,

        Offset = {
            x = 0.0,
            y = 0.0,
            z = 0.0
        },

        Flicker = {
            Enabled = true,
            MinimumMultiplier = 0.96,
            MaximumMultiplier = 1.04,
            UpdateMilliseconds = 75
        }
    }
}

Config.FlareAudio = {
    Enabled = true,
    Required = false,
    Volume = 0.22,
    Distance = 12.0,
    MaximumSources = 4
}
Config.Animations = {
    LoadTimeoutMilliseconds = 5000,

    -- A restrained carry reach; the hand-bone IK target is shared with ignition.
    Carry = { Dictionary = 'bd_roadflare_pose', Clip = 'carry' },
    Place = {
        Dictionary = 'amb@world_human_gardener_plant@male@base',
        Clip = 'base',
        DurationMilliseconds = 1200,
        PlaybackRate = 1.0,
        Flag = 1,
        BlendInSpeed = 3.0,
        BlendOutSpeed = 3.0
    }
}

Config.Timeouts = {
    AuthorizationMilliseconds = 5000,
    PlacementCommitMilliseconds = 5000
}

Config.RateLimits = {
    ActivationMilliseconds = 750,
    PlacementMilliseconds = 500,
    SnapshotMilliseconds = 1000
}

Config.GroundVisuals = {
    Enabled = true,

    ReconcileMilliseconds = 400,
    VisualRetryMilliseconds = 5000,

    ParticleDistance = 80.0,
    LightDistance = 120.0,
    MaximumParticles = 8,
    MaximumLights = 8,
    Particle = { Enabled = true, Asset = 'core', Name = 'proj_flare_fuse',
        Offset = { x = 0.0, y = 0.0, z = 0.22 }, Scale = 0.18 },

    ScopeLostGraceMilliseconds = 1000,
    StartRampMilliseconds = 450,

    UseHeldFlareConfiguration = true,
    UseHeldParticleConfiguration = true,
    UseHeldLightConfiguration = true
}

Config.Permissions = {
    Enabled = false,
    AcePermission = 'bebecito.flares'
}

Config.Distances = {
    Interaction = 2.0,
    Placement = 20.0
}

Config.Placement = {
    RaycastIntervalMilliseconds = 50,
    ResultTimeoutMilliseconds = 500,
    MaximumPreviewAgeMilliseconds = 250,
    MinimumSurfaceNormalZ = 0.65,
    RaycastFlags = 17,
    RaycastOptionFlags = 0,

    Preview = {
        Enabled = true,
        Type = 1,
        HeightOffset = 0.03,
        Scale = {
            x = 0.18,
            y = 0.18,
            z = 0.08
        },
        ValidColor = {
            r = 40,
            g = 220,
            b = 80,
            a = 180
        },
        InvalidColor = {
            r = 220,
            g = 50,
            b = 40,
            a = 150
        }
    }
}

Config.Placing = {
    WalkSpeed = 1.0,

    ArrivalDistance = 0.85,
    PlacementOffsetDistance = 0.55,

    MovementTimeoutMilliseconds = 10000,
    StuckTimeoutMilliseconds = 2500,
    ProgressCheckMilliseconds = 100,

    MinimumProgressDistance = 0.12,

    HeadingTimeoutMilliseconds = 1500,
    HeadingToleranceDegrees = 12.0,

    NavMeshFlags = 0,

    DisableAttackWhilePlacing = true
}

Config.ServerPlacement = {
    MaximumPlayerDistance = 3.0,
    CoordinateAbsoluteLimit = 20000.0,
    SpawnTimeoutMilliseconds = 3000,
    MaximumRetries = 1,
    RecentRequestTtlMilliseconds = 15000,
    MaximumRecentRequestsPerPlayer = 32
}

RoadFlares = RoadFlares or {}


