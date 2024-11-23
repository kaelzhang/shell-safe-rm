const test = require('ava')
const home = require('home')

const factory = require('./cases')

factory(test, 'safe-rm-as', false, undefined, {
  SAFE_RM_TRASH: home.resolve('~/.Trash')
})
