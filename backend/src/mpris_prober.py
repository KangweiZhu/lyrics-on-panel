import dbus
import re
from mpris_player import PlaybackStatus, get_session_bus

def find_players():
    """
    Finds all running media players that implement the MPRIS2 interface.
    """
    try:
        bus = get_session_bus()
        playernames = []
        for s in bus.list_names():
            if re.match('org.mpris.MediaPlayer2.', s):
                playernames.append(s)
        return playernames
    except dbus.exceptions.DBusException:
        return []

def find_playing_players(playernames=None):
    '''
    Finds all running media players that implement the MPRIS2 interface, and current playing something.

    Notice:
    From our implementation, the ordering of players is determined solely by their first appearance in
    the MPRIS DBus via `find_players()` and remains stable across playback state changes. Therefore,
    earlier-registered players always take priority whenever they enter the Playing state.
    '''
    bus = get_session_bus()
    if playernames is None:
        playernames = find_players()
    playing_playernames = []
    for playername in playernames:
        try:
            dbusobj = bus.get_object(playername, '/org/mpris/MediaPlayer2')
            props_iface = dbus.Interface(dbusobj, 'org.freedesktop.DBus.Properties')
            playback_status = props_iface.Get('org.mpris.MediaPlayer2.Player', 'PlaybackStatus')
            if playback_status.lower() == PlaybackStatus.PLAYING.value.lower():
                playing_playernames.append(playername)
        except dbus.exceptions.DBusException:
            continue
    return playing_playernames

