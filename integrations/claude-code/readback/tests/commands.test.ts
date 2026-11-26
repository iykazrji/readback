import { expect, test } from 'claude-code/testing'

type Call = { url: string; body?: unknown }
/** Commands the mod registered with `$.command.register`: none since they became commands/*.md. */
const registered: string[] = []
/** Every POST must say JSON, or the app refuses it (ControlProtocol.swift `parse`). */
const posts: { method?: string; contentType?: string }[] = []

// Each hook stands for the engine beneath the mod: a call on `$` is answered `{ value }`.
// `app` answers the Readback app's HTTP endpoints; undefined means "not running".
function engine(
  on: Parameters<Parameters<typeof test>[1]>[1],
  messages: { role: 'user' | 'assistant'; text: string }[],
  app: ((path: string, body: any) => object | undefined) | undefined,
) {
  const calls: Call[] = []
  const runs: (readonly string[])[] = []
  on('command.register', (_, e) => {
    registered.push(e.name)
    return { value: { command: e.name } }
  })
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
    if (body !== undefined) posts.push({ method: e.init?.method, contentType: (e.init?.headers as any)?.['Content-Type'] })
    const answer = app?.(path, body)
    if (!answer) return { deny: 'connection refused' }
    return { value: { status: 200, ok: true, headers: {}, text: JSON.stringify(answer) } }
  })
  return { calls, runs }
}

// The app writes the answers (ControlProtocol.swift's CommandAnswer); the mod shows them as sent.
const running = (path: string, body: any) => {
  if (path === '/health') return { ok: true, speaking: false }
  if (path === '/command') return { text: `answer to ${body.command}` }
  return { ok: true }
}

async function start($: any) {
  await $.session.start({ cwd: '/Users/me/project', surface: 'terminal', isInteractive: false })
}

test('/readback:speak on sets this session on, explicitly', async ($, on) => {
  const { calls } = engine(on, [], running)
  await start($)
  const { text } = await $.command.run({ command: 'readback:speak', args: 'on' })
  expect(calls.at(-1)).toEqual({ url: '/command', body: { command: 'speak', tool: 'claude', session: 'sess-123', enabled: true } })
  expect(text).toBe('answer to speak')
})

test('/readback:speak with no argument reads the state and never sets it', async ($, on) => {
  const { calls } = engine(on, [], running)
  await start($)
  const { text } = await $.command.run({ command: 'readback:speak', args: '' })
  expect(calls.at(-1)).toEqual({ url: '/command', body: { command: 'speak', tool: 'claude', session: 'sess-123' } })
  expect(text).toBe('answer to speak')
})

test('/readback:speak with anything else explains itself and calls nothing', async ($, on) => {
  const { calls } = engine(on, [], running)
  await start($)
  const { text } = await $.command.run({ command: 'readback:speak', args: 'toggle' })
  expect(calls.length).toBe(0)
  expect(text).toBe('Use /readback:speak on or /readback:speak off.')
})

test('/readback:read sends the last reply with text, for this session', async ($, on) => {
  const { calls } = engine(on, [
    { role: 'user', text: 'hi' },
    { role: 'assistant', text: 'The real answer.' },
    { role: 'user', text: 'thanks' },
    { role: 'assistant', text: '' }, // a tool-call-only message: skipped
  ], running)
  await start($)
  const { text } = await $.command.run({ command: 'readback:read', args: '' })
  expect(calls.at(-1)).toEqual({
    url: '/command',
    body: { command: 'read', tool: 'claude', session: 'sess-123', text: 'The real answer.', cwd: '/Users/me/project' },
  })
  expect(text).toBe('answer to read')
})

test('/readback:read with no reply yet says so and calls nothing', async ($, on) => {
  const { calls } = engine(on, [{ role: 'user', text: 'hi' }], running)
  await start($)
  const { text } = await $.command.run({ command: 'readback:read', args: '' })
  expect(calls.length).toBe(0)
  expect(text).toBe('There is no reply to read yet.')
})

test('when Readback is not running, the mod tries to start it, then says so', async ($, on) => {
  const { runs } = engine(on, [], undefined)
  await start($)
  const { text } = await $.command.run({ command: 'readback:speak', args: 'on' })
  expect(runs[0]).toEqual(['/usr/bin/open', '-g', '-b', 'local.readback', '--args', '--background'])
  expect(text).toMatch(/isn't running/)
})

test('every call with a body is a JSON POST', async ($, on) => {
  posts.length = 0
  engine(on, [{ role: 'assistant', text: 'Hi.' }], running)
  await start($)
  await $.command.run({ command: 'readback:speak', args: 'on' })
  await $.command.run({ command: 'readback:read', args: '' })
  expect(posts.length).toBe(2)
  for (const p of posts) expect(p).toEqual({ method: 'POST', contentType: 'application/json' })
})

test('the mod registers no bare /speak or /read: its commands are /readback:speak and /readback:read', async ($, on) => {
  engine(on, [], running)
  registered.length = 0
  await start($)
  expect(registered).toEqual([])
})
