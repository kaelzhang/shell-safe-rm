const test = require('ava')
const home = require('home')

const run = require('./cases')

run(test, {
  type: 'safe-rm-as',
  env: {
    SAFE_RM_TRASH: home.resolve('~/.Trash')
  }
})
