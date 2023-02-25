/*
Language: Sligh
*/


export default function(hljs) {
  console.log("Running Sligh highlighter")

  const MAIN_KEYWORDS = [
    'process',
    'data',
    'record',
    'if',
    'else',
    'def',
    'end',
    'typescript'
  ];

  const LITERALS = [
    'false',
    'true',
    'null'
  ];

  const TYPES = [
    'Int',
    'Bool',
    'Decimal',
    'String',
    'Set'
  ];

  const KEYWORDS = {
    keyword: MAIN_KEYWORDS,
    literal: LITERALS,
    type: TYPES,
  };

  return {
    name: 'Sligh',
    aliases: [ 'sl' ],
    keywords: KEYWORDS    
  };
}
