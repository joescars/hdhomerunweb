const express = require('express');
const fs = require('fs');
const path = require('path');

const record = require('../hdhomerunRecord');
const recordingStream = require('../recordingStream');

const router = express.Router();
const ID_RE = /^[a-f0-9]+$/i;
const FILE_RE = /^(stream\.m3u8|segment[0-9]+\.ts)$/;

router.get('/recordings', (req, res) => {
  res.set('Cache-Control', 'no-store');
  res.render('recordings', { recordEnabled: record.isConfigured() });
});

router.get('/recordings/fragment', async (req, res) => {
  res.set('Cache-Control', 'no-store');
  if (!record.isConfigured()) return res.render('_recordings_list', { recordings: [], error: 'Recording is not configured on this server.' });
  try {
    res.render('_recordings_list', { recordings: await record.getRecordings(), error: null });
  } catch (err) {
    res.render('_recordings_list', { recordings: [], error: err.message });
  }
});

router.post('/recordings/:id/delete', async (req, res) => {
  const { id } = req.params;
  if (!ID_RE.test(id)) return res.status(400).send('Invalid recording');
  try {
    const recording = await record.getRecording(id);
    if (!recording) return res.status(404).send('Recording not found');
    await record.deleteRecording(id);
    res.render('_recordings_list', { recordings: await record.getRecordings(), error: null });
  } catch (err) {
    res.status(502).send(err.message);
  }
});

router.get('/recordings/:id/watch', async (req, res) => {
  const { id } = req.params;
  if (!ID_RE.test(id)) return res.status(400).send('Invalid recording');
  try {
    const recording = await record.getRecording(id);
    if (!recording) return res.status(404).send('Recording not found');
    res.render('recording-watch', { recording, qualityOptions: Object.keys(recordingStream.PROFILES) });
  } catch (err) {
    res.status(502).send(err.message);
  }
});

router.post('/recordings/:id/:profile/start', (req, res) => {
  const { id, profile } = req.params;
  if (!ID_RE.test(id) || !recordingStream.PROFILES[profile]) return res.status(400).send('Invalid request');
  const sourceUrl = record.getPlaybackUrl(id);
  if (!sourceUrl) return res.status(404).send('Recording not found');
  recordingStream.start(id, sourceUrl, profile);
  res.status(202).end();
});

router.get('/recordings/:id/:profile/ready', (req, res) => {
  const { id, profile } = req.params;
  if (!ID_RE.test(id) || !recordingStream.PROFILES[profile]) return res.status(400).send('Invalid request');
  res.json(recordingStream.isReady(id, profile));
});

router.get('/recordings/:id/:profile/:file', (req, res) => {
  const { id, profile, file } = req.params;
  if (!ID_RE.test(id) || !recordingStream.PROFILES[profile] || !FILE_RE.test(file)) return res.status(400).send('Invalid request');
  const session = recordingStream.get(id, profile);
  if (!session) return res.status(404).end();
  const filePath = path.join(session.dir, file);
  if (!fs.existsSync(filePath)) return res.status(404).end();
  res.set('Cache-Control', 'no-cache');
  res.type(file.endsWith('.m3u8') ? 'application/vnd.apple.mpegurl' : 'video/mp2t');
  fs.createReadStream(filePath).pipe(res);
});

module.exports = router;
