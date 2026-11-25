export type Speaking = boolean

declare module 'claude-code' {
  interface PluginState {
    readback: { speaking: Speaking }
  }
}
