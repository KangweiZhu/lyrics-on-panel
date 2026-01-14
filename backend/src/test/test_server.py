import websockets
import json
import asyncio

BASE = "ws://localhost:23560"


async def test_healthcheck():
    async with websockets.connect(f"{BASE}/healthcheck") as ws:
        resp = await ws.recv()
        data = json.loads(resp)
        print("healthcheck:", data)


async def test_poll():
    async with websockets.connect(f"{BASE}/poll") as ws:
        await ws.send('{}')
        resp = await ws.recv()
        data = json.loads(resp)
        print("poll:", data)


async def test_control_ypm():
    '''
    YesPlayMusic的PlaybackStatus控制存在问题。正常情况下，发送两次play信号, 歌曲仍应处于播放状态；但Yesplaymusic会暂停播放。pause同理。
    '''
    async with websockets.connect(f"{BASE}/control") as ws:
        await ws.send('{"action": "play", "player": "org.mpris.MediaPlayer2.yesplaymusic"}')
        await asyncio.sleep(5)
        await ws.send('{"action": "pause", "player": "org.mpris.MediaPlayer2.yesplaymusic"}')


async def test_control_spotify():
    async with websockets.connect(f"{BASE}/control") as ws:
        await ws.send('{"action": "play", "player": "org.mpris.MediaPlayer2.spotify"}')
        await asyncio.sleep(5)
        await ws.send('{"action": "pause", "player": "org.mpris.MediaPlayer2.spotify"}')


asyncio.run(test_healthcheck())
asyncio.run(test_poll())
asyncio.run(test_control_ypm())
asyncio.run(test_control_spotify())

        
