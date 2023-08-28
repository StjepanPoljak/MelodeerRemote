from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import subprocess
import os.path
import pulsectl

MD_VOLUME_STEP = 0.1

def get_volume():
    with pulsectl.Pulse('get_volume') as pulse:
        sink = pulse.sink_list()[0]
        return sink.volume.value_flat

def set_volume(new_volume):
    with pulsectl.Pulse('set_volume') as pulse:
        sink = pulse.sink_list()[0]
        pulse.volume_set_all_chans(sink, new_volume)

def inc_volume(step):
    curr_vol = get_volume()
    if curr_vol < 1.0:
        if curr_vol + step > 1.0:
            set_volume(1.0)
        else:
            set_volume(curr_vol + step)

def dec_volume(step):
    curr_vol = get_volume()
    if curr_vol > 0.0:
        if curr_vol - step < 0.0:
            set_volume(0.0)
        else:
            set_volume(curr_vol - step)

def split_path(path):
    res = []
    tail = path
    head = ''
    while head:
        tail, head = os.path.split(tail)
        if head:
           res.insert(0, head)
    if tail:
        res.insert(0, tail)
    return res

def killall():
    subprocess.call(['pkill', '-9', 'melodeer-exec'])

MUSIC_PATH = f"/home/pi/Music"

class MelodeerHandler(BaseHTTPRequestHandler):

    def do_POST(self):
        content_length = int(self.headers['Content-Length'])
        data = self.rfile.read(content_length).decode('utf-8')
        received_json = json.loads(data)

        print(received_json)

        curr_dir = os.getcwd()
        os.chdir(MUSIC_PATH)

        files = []
        to_play = []
        status = "OK"
        chdir = "."
        recv_list = list(map( lambda el: el["path"]
                            , received_json['list'])
                            ) if received_json['list'] else []

        if received_json['comm'] == 'killall':
            killall()
        elif received_json['comm'] == 'play':
            to_play = recv_list
        elif received_json['comm'] == 'enter':
            if recv_list and recv_list[0].endswith(".flac"):
                to_play = [ recv_list[0] ]
            else:
                recv_path = recv_list[0] if recv_list else "."
                files = list(map( lambda f: { "path" : f
                                            , "type" : "d" if os.path.isdir(f) else "f"
                                            }
                                , list(map( lambda f: os.path.join(recv_path, f)
                                           , sorted(os.listdir(recv_path))
                                           ))
                                ))
                print(files)
                chdir = recv_path
                status = "list"
        elif received_json['comm'] == 'inc-vol':
            inc_volume(MD_VOLUME_STEP)
        elif received_json['comm'] == 'dec-vol':
            dec_volume(MD_VOLUME_STEP)

        if to_play:
            killall()
            subprocess.Popen(["/usr/local/bin/melodeer-exec", *list(map(lambda f: os.path.join(MUSIC_PATH, f), to_play))])

        # Process received JSON data
        response_json = {
            "status": status,
            "list": files,
            "chdir": { "path": chdir, "type": "d" }
        }

        os.chdir(curr_dir)

        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        self.end_headers()

        response_data = json.dumps(response_json).encode('utf-8')
        self.wfile.write(response_data)

if __name__ == '__main__':
    port = 29486
    server_address = ('', port)
    httpd = HTTPServer(server_address, MelodeerHandler)
    print(f"Server running on port {port}")
    httpd.serve_forever()

