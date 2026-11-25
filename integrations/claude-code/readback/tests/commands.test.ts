import { expect, test } from 'claude-code/testing'

type Call = { url: string; body?: unknown }

// Each hook stands for the engine beneath the mod: a call on `$` is answered `{ value }`.
// `app` answers the Readback app's HTTP endpoints; undefined means "not running".
function engine(
  on: Parameters<Parameters<typeof test>[1]>[1],
  messages: { role: 'user' | 'assistant'; text: string }[],
  app: ((path: string, body: any) => object | undefined) | undefined,
) {
  const calls: Call[] = []
  const runs: (readonly string[])[] = []
  on('command.register', (_, e) => ({ value: { command: e.name } }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('session.id', () => ({ value: 'sess-123' }))
  on('session.messages', () => ({ value: messages.map(m => ({ ...m, toolUses: [] })) }))
  on('clock.sleep', () => ({ value: undefined }))
  on('process.run', (_, e) => {
    runs.push(e.argv)
    return { value: { exitCode: 0, stdout: '', stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  on('http.fetch', (_, e) => {
    const path = e.url.replace('http://127.0.0.1:8908', '')
    const body = e.init?.body ? JSON.parse(e.init.body) : undefined
    calls.push({ url: path, body })
    const answer = app?.(path, body)
    if (!answer) return { deny: 'connection refused' }
    return { value: { status: 200, ok: true, headers: {}, text: JSON.stringify(answer) } }
  })
  return { calls, runs }
}

const running = (path: string, body: any) => {
  if (path === '/health') return { ok: true, speaking: false }
  if (path === '/session') return { session: body.session, enabled: body.enabled ?? false }
  if (path === '/speak') return { accepted: true }
  return { ok: true }
}

async function start($: any) {
  await $.session.start({ cwd: '/Users/me/project', surface: 'terminal', isInteractive: false })
}

test('/speak on sets this session on, explicitly', async ($, on) => {
  const { calls } = engine(on, [], running)
  await start($)
  const { text } = await $.command.run({ command: 'speak', args: 'on' })
  expect(calls.at(-1)).toEqual({ url: '/session', body: { session: 'sess-123', enabled: true } })
  expect(text).toBe('Read-aloud is on for this session.')
})

test('/speak with no argument reads the state and never sets it', async ($, on) => {
  const { calls } = engine(on, [], running)
  await start($)
  const { text } = await $.command.run({ command: 'speak', args: '' })
  expect(calls.at(-1)).toEqual({ url: '/session', body: { session: 'sess-123' } })
  expect(text).toMatch(/off in this session/)
})

test('/speak with anything else explains itself and calls nothing', async ($, on) => {
  const { calls } = engine(on, [], running)
  await start($)
  const { text } = await $.command.run({ command: 'speak', args: 'toggle' })
  expect(calls.length).toBe(0)
  expect(text).toBe('Use /speak on or /speak off.')
})

test('/read sends the last reply with text, for this session', async ($, on) => {
  const { calls } = engine(on, [
    { role: 'user', text: 'hi' },
    { role: 'assistant', text: 'The real answer.' },
    { role: 'user', text: 'thanks' },
    { role: 'assistant', text: '' }, // a tool-call-only message: skipped
  ], running)
  await start($)
  const { text } = await $.command.run({ command: 'read', args: '' })
  expect(calls.at(-1)).toEqual({
    url: '/speak',
    body: { text: 'The real answer.', source: 'claude', session: 'sess-123', cwd: '/Users/me/project', autoplay: true },
  })
  expect(text).toBe('Reading the last reply.')
})

test('/read with no reply yet says so and calls nothing', async ($, on) => {
  const { calls } = engine(on, [{ role: 'user', text: 'hi' }], running)
  await start($)
  const { text } = await $.command.run({ command: 'read', args: '' })
  expect(calls.length).toBe(0)
  expect(text).toBe('There is no reply to read yet.')
})

test('when Readback is not running, the mod tries to start it, then says so', async ($, on) => {
  const { runs } = engine(on, [], undefined)
  await start($)
  const { text } = await $.command.run({ command: 'speak', args: 'on' })
  expect(runs[0]).toEqual(['/usr/bin/open', '-g', '-b', 'local.readback', '--args', '--background'])
  expect(text).toMatch(/isn't running/)
})
