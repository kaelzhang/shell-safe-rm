const test = require('ava')

const factory = require('./cases')

factory(test, 'rm', false, '/bin/rm')