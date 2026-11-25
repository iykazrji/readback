import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register, Timer } from 'claude-code'

// Readback for Claude Code: read-aloud per session, off by default.
//
//   /readback:speak on | off   switches it for this session (an explicit set, never a toggle)
//   /readback:speak            says whether it's on here
//   /readback:read             reads the last reply now, whatever the switch says
//
// The commands are the files in commands/, which Claude Code names after the plugin. The hooks
// below answer them before they're rendered, so they never reach the model; the files' own text
// is only a fallback for a session where this module didn't load. (Owner, 2026-11-25: the bare
// /speak and /read went away for these names. A name registered with $.command.register can't
// hold a colon, which is why they're files.)
//
// Readback.app does the reading; this mod talks to it on 127.0.0.1:8908 and starts it when it
// isn't running. The Stop hook Readback adds to settings.json hands each finished reply to the
// app, which reads it when this session (or "every Claude Code reply") is switched on. The
// commands go to the app's /command, which also answers Codex's, so both tools say the same thing.
// While this session's reply plays, the band above the prompt shows "Reading aloud · 0: Stop".

const BASE = 'http://127.0.0.1:8908'
const speaking = atom({ plugin: 'readback', key: 'speaking' } as const, false)

type Health = { speaking?: boolean; session?: string | null }

/** Calls the Readback app. Returns the parsed answer, or undefined when it can't be reached. */
async function call($: EngineInterface, path: string, body?: object): Promise<Record<string, unknown> | undefined> {
  try {
    const res = await $.http.fetch(
      BASE + path,
      body === undefined ? {} : { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) },
    )
    if (!res.ok) {
      $.ui.log(`readback: ${path} answered HTTP ${res.status}`)
      return undefined
    }
    return JSON.parse(res.text) as Record<string, unknown>
  } catch {
    return undefined // not running; callers decide whether that's worth saying
  }
}

/** Starts Readback in the background if it isn't answering, and waits up to 4 seconds. */
async function reachApp($: EngineInterface): Promise<boolean> {
  if (await call($, '/health')) return true
  const { exitCode, stderr } = await $.process.run(['/usr/bin/open', '-g', '-b', 'local.readback', '--args', '--background'])
  if (exitCode !== 0) {
    $.ui.log(`readback: couldn't start Readback.app: ${stderr.trim()}`)
    return false
  }
  for (let i = 0; i < 16; i++) {
    await $.clock.sleep(250)
    if (await call($, '/health')) return true
  }
  $.ui.log('readback: Readback.app started but did not answer')
  return false
}

const NOT_RUNNING = "Readback isn't running and couldn't be started. Open Readback from your Applications folder."

export const register: Register = on => {
  let poll: Timer | undefined
  let me = ''
  let cwd = ''

  on('session.start', async ($, e, next) => {
    const result = await next(e)
    me = await $.session.id()
    cwd = e.cwd

    if (!e.isInteractive) return result
    poll?.cancel()
    // Readback not answering is a normal state (the person quit it), not an error: the band
    // just doesn't show. The commands say so when they need the app.
    poll = $.clock.every(500, async () => {
      const health = (await call($, '/health')) as Health | undefined
      const now = health?.speaking === true && health.session === me
      if (now !== (await read($, speaking))) await update($, speaking, () => now)
    })
    return result
  })

  on('command.run', { command: 'readback:speak' }, async ($, e) => {
    const arg = e.args.trim().toLowerCase()
    if (arg !== '' && arg !== 'on' && arg !== 'off') return { text: 'Use /readback:speak on or /readback:speak off.' }
    if (!(await reachApp($))) return { text: NOT_RUNNING }
    const asked = arg === '' ? {} : { enabled: arg === 'on' }
    const answer = await call($, '/command', { command: 'speak', tool: 'claude', session: me, ...asked })
    return { text: typeof answer?.text === 'string' ? answer.text : "Readback didn't answer. See ~/Library/Logs/Readback." }
  }).catch(() => ({ text: "Readback couldn't answer that. See ~/Library/Logs/Readback." }))

  on('command.run', { command: 'readback:read' }, async $ => {
    const messages = await $.session.messages({ last: 40 })
    if ('deny' in messages) return { text: "Couldn't read this session's messages." }
    const last = messages.findLast(m => m.role === 'assistant' && m.text.trim() !== '')
    if (!last) return { text: 'There is no reply to read yet.' }
    if (!(await reachApp($))) return { text: NOT_RUNNING }
    // The text goes too: if Readback wasn't running when the reply finished, it never got it.
    const answer = await call($, '/command', { command: 'read', tool: 'claude', session: me, text: last.text, cwd })
    return { text: typeof answer?.text === 'string' ? answer.text : "Readback didn't take it. See ~/Library/Logs/Readback." }
  }).catch(() => ({ text: "Readback couldn't answer that. See ~/Library/Logs/Readback." }))

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    if (e.props.hasSurvey || !(await read($, speaking))) return next(e)
    const { Box, Button, Text } = $.ui.resolve(e)
    const stop = async () => {
      if (!(await call($, '/stop', { session: me }))) $.ui.log("readback: couldn't reach Readback to stop it")
      await update($, speaking, () => false)
    }
    return (
      <Box>
        <Text dimColor>Reading aloud · </Text>
        <Button key="stop" label="Stop" hotkey="0" plain onPress={stop} />
      </Box>
    )
  })
}
