const PM2 = require('../..');
const should = require('should');
const path = require('path');
const sleep = ms => new Promise(r => setTimeout(r, ms));

describe('restart delay manual restart behavior', function() {
  var pm2;
  const fixtures_path = path.join(__dirname, 'fixtures', 'restart-delay');

  after(function(done) {
    pm2.delete('all', function() {
      pm2.kill(done);
    });
  });

  before(function(done) {
    pm2 = new PM2.custom({ cwd: fixtures_path });

    pm2.delete('all', () => done());
  });

  it('should allow manual restart while waiting restart (restart_delay)', async function() {
    this.timeout(10000);

    // Start app with restart_delay so it will go to WAITING_RESTART after crash
    await new Promise((resolve, reject) => {
      pm2.start({
        script: path.join(fixtures_path, 'wrong.js'),
        name: 'wrongtest',
        restart_delay: 500
      }, function(err, apps) {
        if (err) return reject(err);
        resolve(apps);
      });
    });

    // Wait until process enters WAITING_RESTART, up to timeout
    const waitForStatus = (name, expectedStatus, timeout = 5000) => new Promise((resolve, reject) => {
      let elapsed = 0;
      const interval = 100;
      const check = () => {
        pm2.list((err, procs) => {
          if (err) return reject(err);
          const proc = procs.find(p => p.name === name);
          if (proc && proc.pm2_env && proc.pm2_env.status === expectedStatus) return resolve(proc);
          elapsed += interval;
          if (elapsed >= timeout) return reject(new Error('Timeout waiting for status ' + expectedStatus));
          setTimeout(check, interval);
        });
      };
      check();
    });

    const target = await waitForStatus('wrongtest', 'waiting restart', 5000);

    // Try a manual restart while waiting restart using pm_id to avoid name lookup issues
    await new Promise((resolve, reject) => pm2.restart(target.pm_id, (err) => err ? reject(err) : resolve()));

    // Wait a bit to let it start
    await sleep(400);

    const list2 = await new Promise((resolve) => pm2.list((err, procs) => resolve(procs)));
    const t2 = list2.find(p => p.name === 'wrongtest');
    should.exist(t2);
    // Either online or still restarting, but not in waiting restart stuck state
    const validStatuses = ['online', 'launching', 'stopped', 'errored'];
    validStatuses.indexOf(t2.pm2_env.status).should.be.aboveOrEqual(0);
  });
});
