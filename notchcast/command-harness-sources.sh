# Sourced by upstream's runner for each harness, so fork sources an upstream file needs never need a shared registration.
# The hidden tabs (notchcast/docs/hidden.md) and Notchcast's own tabs sit beside SettingsTab: a harness compiling it gets them.
if [[ " $* " == *" Tinycast/Features/Settings/SettingsTab.swift "* && " $* " != *" Tinycast/Features/Notchcast/Hidden/NotchcastHidden.swift "* ]]; then
    set -- "$@" Tinycast/Features/Notchcast/Hidden/NotchcastHidden.swift
fi
if [[ " $* " == *" Tinycast/Features/Settings/SettingsTab.swift "* && " $* " != *" Tinycast/Features/Notchcast/Core/Model/NotchcastPane.swift "* ]]; then
    set -- "$@" Tinycast/Features/Notchcast/Core/Model/NotchcastPane.swift
    [[ " $* " == *" Tinycast/Features/Notchcast/Core/Model/NotchcastCategory.swift "* ]] || set -- "$@" Tinycast/Features/Notchcast/Core/Model/NotchcastCategory.swift
fi
# Notchcast's search rows sit beside the catalog, with the two descriptor types they read.
if [[ " $* " == *" Tinycast/Features/Settings/SettingsSearchCatalog.swift "* && " $* " != *" Tinycast/Features/Notchcast/Core/UI/NotchcastSettingsSearch.swift "* ]]; then
    set -- "$@" Tinycast/Features/Notchcast/Core/UI/NotchcastSettingsSearch.swift
    [[ " $* " == *" Tinycast/Features/Notchcast/Core/Model/NotchcastSwitch.swift "* ]] || set -- "$@" Tinycast/Features/Notchcast/Core/Model/NotchcastSwitch.swift
    [[ " $* " == *" Tinycast/Features/Notchcast/Core/Model/NotchcastCategory.swift "* ]] || set -- "$@" Tinycast/Features/Notchcast/Core/Model/NotchcastCategory.swift
fi
# `frosted(in:)` paints the island's black through the island glass, and Theme reads OBSIDIAN tokens.
if [[ " $* " == *" Tinycast/DesignSystem/Theme.swift "* || " $* " == *" Tinycast/Features/Island/Service/IslandPaletteSurface.swift "* ]]; then
    [[ " $* " == *" Tinycast/Features/Island/Service/IslandPaletteSurface.swift "* ]] || set -- "$@" Tinycast/Features/Island/Service/IslandPaletteSurface.swift
    [[ " $* " == *" Tinycast/Features/Notchcast/NotchTheme.swift "* ]] || set -- "$@" Tinycast/Features/Notchcast/NotchTheme.swift
    [[ " $* " == *" Tinycast/DesignSystem/ObsidianTokens.swift "* ]] || set -- "$@" Tinycast/DesignSystem/ObsidianTokens.swift
fi
# Upstream's icon pack tints Theme and SettingsTab with IconTint, so either brings it along.
if [[ " $* " == *" Tinycast/DesignSystem/Theme.swift "* || " $* " == *" Tinycast/Features/Settings/SettingsTab.swift "* ]]; then
    [[ " $* " == *" Tinycast/DesignSystem/IconTint.swift "* ]] || set -- "$@" Tinycast/DesignSystem/IconTint.swift
fi
