from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import subprocess
import os.path
import tempfile
import shutil
import threading

PLAY_LOOP = False
PLAY_LOOP_LOCK = threading.Lock()
MUSIC_PATH = f"/media"
VOLUME_STEP=5

def set_play_loop(val):
    global PLAY_LOOP
    with PLAY_LOOP_LOCK:
        PLAY_LOOP = val

def play_thread(to_play, event):
    global PLAY_LOOP
    killall()
    set_play_loop(True)
    got_first = False
    for f in to_play:
        with PLAY_LOOP_LOCK:
            if not PLAY_LOOP:
                break
        with tempfile.NamedTemporaryFile(suffix=".flac", delete=False) as temp_file:
            shutil.copy(os.path.join(MUSIC_PATH, f), temp_file.name)
            if not got_first:
                got_first = True
                event.set()
            proc = subprocess.Popen(["sndfile-play", temp_file.name])
            proc.wait()

def get_volume():
    return int(subprocess.check_output(["amixer", "sget", "'Digital',0"]).decode("utf-8").split("[")[1].split("%")[0])

def set_volume(new_volume):
    subprocess.call(["amixer", "-q", "sset", "'Digital',0", f"{new_volume}%"])
    subprocess.call(["amixer", "sget", "'Digital',0"])

def dec_volume(step):
    set_volume(max(0, get_volume() - VOLUME_STEP))

def inc_volume(step):
    set_volume(min(100, get_volume() + VOLUME_STEP))

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
    global PLAY_LOOP
    subprocess.call(['pkill', '-9', 'sndfile-play'])
    set_play_loop(False)

class MelodeerHandler(BaseHTTPRequestHandler):

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.timeout = 60

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
            event = threading.Event()
            thread = threading.Thread(target=play_thread, args=(to_play, event))
            thread.start()
            event.wait()

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

