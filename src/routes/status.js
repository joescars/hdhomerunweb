const express = require('express');
const hdhr = require('../hdhomerun');

const router = express.Router();

router.get('/status', async (req, res) => {
  try {
    const tuners = await hdhr.getTunerStatus();
    res.render('status', { tuners: tuners || [], error: null });
  } catch (err) {
    res.render('status', { tuners: [], error: err.message });
  }
});

router.get('/status/fragment', async (req, res) => {
  try {
    const tuners = await hdhr.getTunerStatus();
    res.render('_tuner_status', { tuners: tuners || [], error: null });
  } catch (err) {
    res.render('_tuner_status', { tuners: [], error: err.message });
  }
});

module.exports = router;
