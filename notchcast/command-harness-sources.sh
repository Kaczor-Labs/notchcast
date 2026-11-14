# Sourced by upstream's runner for each harness, so fork sources an upstream file needs never need a shared registration.
# The hidden tabs (notchcast/docs/hidden.md) sit beside SettingsTab: a harness compiling it gets them.
if [[ " $* " == *" Tinycast/Features/Settings/SettingsTab.swift "* && " $* " != *" Tinycast/Features/Notchcast/Hidden/NotchcastHidden.swift "* ]]; then
    set -- "$@" Tinycast/Features/Notchcast/Hidden/NotchcastHidden.swift
fi
