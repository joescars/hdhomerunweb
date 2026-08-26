const express = require('express');
const hdhr = require('../hdhomerun');

const router = express.Router();

router.get('/scan', async (req, res) => {
  try {
    const status = await hdhr.getLineupStatus();
    res.render('scan', { status, error: null });
  } catch (err) {
    res.render('scan', { status: null, error: err.message });
  }
});

router.get('/scan/status', async (req, res) => {
  try {
    const status = await hdhr.getLineupStatus();
    res.render('_scan_status', { status, error: null });
  } catch (err) {
    res.render('_scan_status', { status: null, error: err.message });
  }
});

router.post('/scan/start', async (req, res) => {
  try {
    await hdhr.startScan(req.body.source);
    const status = await hdhr.getLineupStatus();
    res.render('_scan_status', { status, error: null });
  } catch (err) {
    res.render('_scan_status', { status: null, error: err.message });
  }
});

router.post('/scan/abort', async (req, res) => {
  try {
    await hdhr.abortScan();
    const status = await hdhr.getLineupStatus();
    res.render('_scan_status', { status, error: null });
  } catch (err) {
    res.render('_scan_status', { status: null, error: err.message });
  }
});

module.exports = router;
