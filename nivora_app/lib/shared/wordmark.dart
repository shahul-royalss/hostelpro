import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_parsing/path_parsing.dart';

/// The NIVORA signature, and the machinery to draw it as if it were being written.
///
/// ── WHY THE PATH DATA IS A STRING HERE ────────────────────────────────────────────────────
///
/// This is the same outline the website draws on its sign-in screen, carried verbatim so the two
/// cannot drift into two slightly different signatures. It is deliberately NOT an .svg asset,
/// because the point is not to show the shape — it is to DRAW it, and that needs a [ui.Path]
/// whose length can be measured and taken a fraction at a time. flutter_svg renders a picture;
/// it does not hand back geometry.
///
/// The web version animates `stroke-dashoffset` from 1 to 0 against `pathLength="1"`, which
/// normalises the WHOLE outline to unit length — so the stroke is laid down continuously from
/// the first letter to the last rather than every letter growing at once. [NivoraWordmark]
/// reproduces exactly that by walking the sub-paths in order and spending one shared budget
/// across them.
const String kNivoraWordmarkPath =
    'M5.5 82.8L5.5 82.8Q4.5 81.7 4.2 80.9Q3.9 80.2 4.1 79.1Q4.4 78.1 4.9 76.2L4.9 76.2Q5.7 73 '
    '6.6 70.8Q7.6 68.7 8.5 66.3Q9.5 64 10.2 60.3L10.2 60.3Q11.8 56.6 13 53.3Q14.3 50 15 '
    '47.9Q15.7 45.8 15.7 45.8L15.7 45.8Q15.8 45.4 16.6 43.7Q17.4 42 18.6 39.5Q19.9 37.1 21 '
    '34.6L21 34.6Q22.7 29.8 23.7 26.3Q24.8 22.9 25.9 20.1Q27 17.3 28.8 14.6L28.8 14.6Q30 12.5 '
    '31.6 11.9Q33.2 11.3 34.6 11.9Q36.1 12.6 36.7 14.6L36.7 14.6Q37.2 15.6 37.5 17Q37.9 18.4 '
    '38.2 21Q38.5 23.7 38.6 28.5L38.6 28.5Q38.8 34.2 38.7 39.7Q38.6 45.3 38.7 50Q38.9 54.7 39.8 '
    '58L39.8 58Q40.1 59.8 40.6 62.3Q41.2 64.9 41.8 67.4Q42.5 69.9 43.1 71.6Q43.8 73.3 44.2 '
    '73.3L44.2 73.3Q44.7 73.3 45.5 72Q46.4 70.7 47.7 67.3Q49.1 63.9 51 57.6Q52.9 51.4 55.3 '
    '41.6L55.3 41.6Q55.8 39.9 56.6 36.1Q57.5 32.3 57.9 28.4L57.9 28.4Q58.6 25.9 59.3 22.9Q60 '
    '19.9 60.5 17.6Q61.1 15.3 61.1 15L61.1 15Q61.1 14.3 61.1 13.8Q61.2 13.3 61.1 12.8L61.1 '
    '12.8Q61.6 12.8 62 11.4Q62.4 10.1 62.4 9.1L62.4 9.1Q62.4 7.4 62.8 6.3Q63.3 5.3 63.8 4.8L63.8 '
    '4.8Q64.1 4 65.3 4Q66.5 4.1 67.7 4.7Q68.9 5.3 69.2 6.3L69.2 6.3Q69.4 7.4 68.6 11.2Q67.9 15.1 '
    '66.4 21.6L66.4 21.6Q66.4 22.7 65.8 25.2Q65.2 27.7 64.5 30.5Q63.9 33.3 63.6 35.3L63.6 '
    '35.3Q63.2 37.9 62.7 40.1Q62.2 42.4 61.7 42.3L61.7 42.3Q59.1 53.6 56.2 61.5Q53.4 69.5 51.2 '
    '74.5L51.2 74.5Q48.8 80 45.9 81.1Q43.1 82.3 39.9 78.2L39.9 78.2Q38 75.6 36.9 73Q35.8 70.5 '
    '35.1 67Q34.4 63.6 33.4 58.5L33.4 58.5Q31.9 54.4 31.7 50.2Q31.6 46 32 41.5Q32.4 37.1 32.6 '
    '32.3L32.6 32.3Q32.5 27.5 32.2 25.9Q31.9 24.3 31 26Q30.2 27.8 28.3 33.1L28.3 33.1Q27.6 35 '
    '26.4 37.7Q25.3 40.4 24.2 43Q23.1 45.7 22.3 47.6Q21.5 49.6 21.3 50.1L21.3 50.1Q20.7 51.3 '
    '19.9 53.2Q19.1 55.2 18.6 57.4L18.6 57.4Q15 66.8 13.2 72.4Q11.5 78 10.7 80.2L10.7 80.2Q9.7 '
    '83 8.6 83.9Q7.5 84.9 5.5 82.8M74.9 79.7L74.9 79.7Q74.2 78.6 71.7 78.3Q69.3 78 65.8 78.2L65.8 '
    '78.2Q64.4 78.4 63.1 78Q61.8 77.7 61 76.9Q60.3 76.2 60.5 75.4L60.5 75.4Q60.6 74.2 62.5 '
    '73.5Q64.5 72.8 68.8 72.7L68.8 72.7L74.1 72.6L75.1 70.6Q75.5 69.5 76.1 67.5Q76.7 65.5 77.4 '
    '63.2L77.4 63.2Q77.8 61.8 78.6 59.4Q79.4 57 80.3 54.3Q81.2 51.6 81.9 49.4Q82.6 47.3 82.8 '
    '46.4L82.8 46.4Q83.2 45.5 83.9 43.3Q84.6 41.2 85.2 38.9Q85.9 36.7 86.1 35.7L86.1 35.7Q88.7 '
    '27.8 89.5 24.4Q90.3 21.1 89.9 21L89.9 21Q89.5 21 87.9 21.1Q86.4 21.2 84.5 21.3Q82.7 21.5 '
    '81.2 21.7Q79.8 21.9 79.5 22.1L79.5 22.1Q79 22.8 77.8 22.4Q76.6 22 76.3 21L76.3 21Q76.2 20.1 '
    '76.2 19.6Q76.3 19.1 76.8 18.8L76.8 18.8Q77.5 18.2 79.5 17.4Q81.5 16.7 84 16.1Q86.6 15.5 '
    '88.9 15.2L88.9 15.2Q90.6 15 92.3 14.4Q94 13.9 95 13.1L95 13.1Q95.9 12.8 96.7 12.6Q97.6 12.4 '
    '98.5 12.5L98.5 12.5Q99.3 13 101.2 13Q103.2 13 105.4 12.9L105.4 12.9Q111 12.4 112.9 '
    '12.6Q114.9 12.8 115.6 14.2L115.6 14.2Q116.1 16.1 115.8 17.1Q115.5 18.2 113.8 18.1L113.8 '
    '18.1Q112.9 18.3 110.5 18.4Q108.2 18.6 105.6 18.7L105.6 18.7Q98.5 19.3 98 20.1L98 20.1Q97.6 '
    '20.5 97.3 20.9Q97.1 21.3 96.7 21.8L96.7 21.8Q96.8 22.2 96.2 24.3Q95.7 26.5 94.9 28.7L94.9 '
    '28.7Q94.5 30 93.7 32.4Q92.9 34.8 92 37.3Q91.2 39.9 90.5 41.9Q89.8 44 89.5 44.7L89.5 '
    '44.7Q89.1 45.6 88.8 46.6Q88.6 47.7 88.5 48.2L88.5 48.2Q87.1 53.1 86 56.5Q85 59.9 84.1 '
    '62.4Q83.3 65 82.6 67.3Q81.9 69.7 81.1 72.5L81.1 72.5Q81.1 72.5 82.6 72.3Q84.2 72.2 86.8 '
    '72L86.8 72Q91.5 71.5 93.5 71.4Q95.6 71.3 96.3 71.6Q97 72 97.3 72.9L97.3 72.9Q99.3 75.6 97.8 '
    '76.6Q96.3 77.6 90.7 77.5L90.7 77.5Q85.5 77.7 82.7 77.8Q80 78 78.9 78.3Q77.9 78.6 77.7 '
    '79.3L77.7 79.3Q77.7 80.1 76.9 80.1Q76.1 80.1 74.9 79.7M124.7 82.4L124.7 82.4Q124.2 82.2 124 '
    '81.8Q123.8 81.4 123.6 80.2L123.6 80.2Q123.6 79.1 123 78.6Q122.4 78.1 120.7 77.7L120.7 '
    '77.7Q119.6 76.6 119.1 75.2Q118.6 73.8 118.3 70.6Q118.1 67.4 117.7 61L117.7 61Q117.9 57.5 118 '
    '55.1Q118.2 52.7 118.4 50.6Q118.6 48.5 118.8 46.1Q119.1 43.7 119.6 40.1L119.6 40.1Q119.4 37.8 '
    '119.8 35.1Q120.3 32.4 120 30.8L120 30.8Q120.7 28.6 120.9 25.7Q121.1 22.9 121.8 20.7L121.8 '
    '20.7Q122 19 122.2 17.5Q122.5 16 122.5 15L122.5 15Q122.3 13 122.7 11.3Q123.1 9.6 124.3 '
    '9.1L124.3 9.1Q124.9 8.9 126 8.8Q127.1 8.7 127.6 9.1L127.6 9.1Q128.4 9.5 128.7 10.4Q129 11.3 '
    '128.9 12.4L128.9 12.4Q129.1 13.5 128.9 16.2Q128.8 18.9 128.4 22.1Q128 25.4 127.3 28.5L127.3 '
    '28.5Q126.5 32.6 126 36.8Q125.6 41.1 125.4 45.2L125.4 45.2Q125 53.4 124.6 58.8Q124.2 64.2 '
    '124.5 66.6L124.5 66.6Q124.5 66.9 124.7 68.2Q124.9 69.5 125.2 70.6Q125.5 71.8 125.8 71.8L125.8 '
    '71.8Q126.6 71.7 127.3 70.4Q128.1 69.1 128.7 67.3Q129.4 65.6 130 64.3L130 64.3Q131.3 61.8 '
    '132.6 58.8Q134 55.9 135 53.2L135 53.2Q136.8 49 138.6 46Q140.4 43 142 39.3L142 39.3Q142.6 '
    '37.7 144.1 34.6Q145.7 31.6 147.1 29L147.1 29Q148.8 26.4 150.3 24Q151.9 21.6 154 17.6L154 '
    '17.6Q156.9 12.8 158.5 11Q160.1 9.2 161.7 9.2L161.7 9.2Q162.8 9 163 9.1Q163.3 9.3 164 '
    '10.3L164 10.3Q164.8 11.4 164.8 12.5Q164.9 13.7 163.8 15.7Q162.8 17.7 160.2 21.4L160.2 '
    '21.4Q158.2 24.4 155.7 28.4Q153.3 32.4 151.2 35.9Q149.2 39.5 148.3 41.2L148.3 41.2Q147.8 42.3 '
    '147.4 43.5Q147 44.7 146.2 45.7L146.2 45.7Q145.2 46.7 143.5 50Q141.8 53.3 140.2 56.5L140.2 '
    '56.5Q138.4 60.7 137.3 63Q136.3 65.4 135.6 66.9Q135 68.4 134.4 69.8Q133.8 71.2 132.9 '
    '73.3L132.9 73.3Q132.4 75 131.5 76.8Q130.7 78.7 130.6 79.3L130.6 79.3Q129.9 80.4 128.7 '
    '81.2Q127.6 82.1 126.5 82.4Q125.4 82.7 124.7 82.4M164.2 78.6L164.2 78.6Q160.5 75.8 159.5 '
    '74.2Q158.5 72.7 158.3 70.5L158.3 70.5Q158.1 68.7 158.3 65.6Q158.6 62.5 159 59.5Q159.4 56.5 '
    '159.7 55L159.7 55Q160.2 54.5 160.1 53.6Q160.1 52.8 160.1 52.8L160.1 52.8Q160 52.3 160.8 '
    '50.1Q161.6 48 162.3 44.6L162.3 44.6Q164.3 38.6 166.1 34.5Q168 30.5 169.8 27.6Q171.6 24.7 '
    '173.4 22.3L173.4 22.3Q177.5 18.1 180 15.9Q182.5 13.8 185.6 12.4L185.6 12.4Q187.6 11.2 189.3 '
    '10.5Q191 9.8 192.1 10.3L192.1 10.3Q197.7 11.5 200.5 14.8Q203.3 18.2 204.6 25.2L204.6 '
    '25.2Q205.3 29.6 205.4 33.1Q205.6 36.7 204.9 40.1Q204.2 43.6 202.3 47.7Q200.5 51.8 197.2 '
    '57.3L197.2 57.3Q193.7 64.2 189.3 69.3Q185 74.4 180.4 77.3Q175.9 80.3 171.6 80.7Q167.4 81.1 '
    '164.2 78.6M170.6 75.7L170.6 75.7Q172.9 75.4 175 74.3Q177.1 73.2 179.4 71Q181.7 68.9 184.6 '
    '65.6L184.6 65.6Q187.2 62.6 188.8 60.5Q190.5 58.5 191.6 56.4Q192.8 54.3 193.8 51.3Q194.9 48.3 '
    '196.3 43.5L196.3 43.5Q197.1 40.5 197.5 38.5Q197.9 36.5 198 34.7Q198.1 33 198 30.7Q198 28.4 '
    '198 24.8L198 24.8Q197.9 23.1 197.3 21.2Q196.7 19.4 195.9 18.5L195.9 18.5Q194.9 17.4 193.1 '
    '16.9Q191.3 16.5 189.1 17.5L189.1 17.5Q187.9 18 186 19.7Q184.1 21.5 182 23.8Q179.9 26.1 178 '
    '28.5Q176.2 30.9 175 32.7Q173.9 34.6 173.9 35.3L173.9 35.3Q173.9 35.3 173.8 35.8Q173.8 36.3 '
    '173.4 36.8L173.4 36.8Q172.1 38.2 170.5 41.8Q169 45.4 167.6 49.9Q166.2 54.5 165.2 58.9Q164.3 '
    '63.4 164.1 66.7L164.1 66.7Q163.9 69.4 163.9 70.4Q163.9 71.4 164.3 71.9Q164.7 72.5 165.6 '
    '74L165.6 74Q166.2 75 167.6 75.5Q169.1 76 170.6 75.7M210.3 82.6L210.3 82.6Q209.9 83.6 208.8 '
    '83.7Q207.8 83.8 206.1 82.5L206.1 82.5Q204.9 81.3 204.5 80.6Q204.2 80 204.9 78.4Q205.6 76.9 '
    '207.3 73L207.3 73Q207.7 70.6 208.7 68.1Q209.7 65.7 210.2 64.7L210.2 64.7Q210.6 63.3 211.8 '
    '60Q213.1 56.8 214.7 52.8Q216.4 48.8 217.9 45.2Q219.4 41.7 220.1 39.9L220.1 39.9Q221.8 35.9 '
    '223.6 31.5Q225.4 27.1 228.5 20.4L228.5 20.4Q228.9 19.4 228.9 18.3Q229 17.2 227.3 17.2L227.3 '
    '17.2Q226.3 16.1 226.2 14.9Q226.1 13.8 227.2 13.3L227.2 13.3L232.4 11.2Q237.1 10.1 242 '
    '10.5Q247 11 251.4 13.3L251.4 13.3Q256.2 16.1 258.2 18.9Q260.2 21.8 260.2 24.7Q260.3 27.6 '
    '259.2 30.4L259.2 30.4Q258.4 32.5 256.1 35Q253.9 37.5 250.9 40Q248 42.5 244.8 44.5Q241.7 46.6 '
    '239 47.7L239 47.7Q236.5 48.9 233.8 49.8Q231.1 50.7 228.2 51.6L228.2 51.6Q226.6 52 224.4 '
    '52Q222.2 52 221.1 51.6L221.1 51.6L219.4 56.3Q218.4 59.9 215.9 67Q213.5 74.1 210.3 82.6M250 '
    '83.7L250 83.7Q249.2 84 248.1 83.9Q247.1 83.8 244.8 82.3L244.8 82.3Q240.4 79.7 236 76Q231.6 '
    '72.3 226.1 66L226.1 66Q224 63.5 222.5 61.4Q221.1 59.3 219.5 55.5L219.5 55.5L218.1 50.1L220.8 '
    '48.6L224.4 52.2Q226 55.7 228.5 58.9Q231.1 62.1 233.3 64.6L233.3 64.6Q235.1 66.7 238.2 '
    '69.6Q241.3 72.6 244.8 75.3Q248.3 78 251.1 79.4L251.1 79.4Q251.7 79.9 251.5 80.9Q251.3 81.9 '
    '250.8 82.7Q250.4 83.6 250 83.7M224.2 46.5L224.2 46.5Q226.5 46.3 229.6 45.3Q232.7 44.4 235.8 '
    '43.1L235.8 43.1Q238.7 41.7 241.9 39.7Q245.2 37.8 248 35.4Q250.8 33 252.5 30.4Q254.3 27.8 '
    '254.1 25.2L254.1 25.2Q254.1 23.9 253.1 22.5Q252.1 21.1 250.7 20Q249.3 18.9 248 18.5L248 '
    '18.5Q244 17.5 241.4 17.2Q238.8 16.9 237.4 17.5Q236 18.2 235.5 20.2L235.5 20.2Q235.5 20.5 '
    '234.7 22.2Q233.9 23.9 232.7 26.4Q231.6 28.9 230.5 31.7L230.5 31.7Q227.6 37.6 226.1 40.6Q224.6 '
    '43.7 224.2 44.9Q223.8 46.1 224.2 46.5M256 81.1L254.4 79.9Q252.6 78.9 252.4 77.7Q252.3 76.5 '
    '253.8 73.5Q255.3 70.5 258.5 64.2L258.5 64.2Q260.9 59.7 262.1 57.1Q263.4 54.6 263.8 53.5Q264.3 '
    '52.4 264.3 52.1L264.3 52.1Q264.1 51.2 264.5 50.6Q264.9 50.1 265.8 49.7L265.8 49.7Q266.3 49.2 '
    '267.4 47.9Q268.6 46.6 269.6 44.8L269.6 44.8Q270.5 42.7 271.7 40.5Q272.9 38.3 274.9 34.9Q276.9 '
    '31.6 280.1 26.2L280.1 26.2Q282.1 22.7 284.5 19Q286.9 15.4 289.6 11.8L289.6 11.8Q290.7 10.4 '
    '291.6 9.5Q292.5 8.7 293.4 8.8L293.4 8.8Q294.6 8.8 296.1 9.6Q297.7 10.4 299 11.7Q300.3 13 '
    '300.9 14.5L300.9 14.5Q301.4 15.3 301.3 17.9Q301.2 20.5 300.9 24.2Q300.6 27.9 300.2 32.1L300.2 '
    '32.1Q299.9 36.2 299.3 41.8Q298.7 47.4 298.1 53.5Q297.6 59.6 297.3 65.2Q297 70.9 297.3 '
    '75.1L297.3 75.1Q297.4 76 297.3 76.8Q297.2 77.6 297.2 78.1L297.2 78.1Q296.6 78.7 295.2 '
    '78.6Q293.9 78.6 292.6 78Q291.4 77.4 291.2 76.5L291.2 76.5Q290.9 76.2 290.8 75.6Q290.8 75.1 '
    '290.9 73.3Q291 71.5 291.1 67.6L291.1 67.6L291.6 51.4L290.3 51.5Q289.4 51.5 286.9 51.7Q284.4 '
    '51.9 281.5 52.2Q278.6 52.6 276.1 52.9Q273.7 53.3 272.8 53.6L272.8 53.6Q271.9 53.6 270.6 '
    '54.8Q269.4 56 268.3 57.9L268.3 57.9Q267.9 59.3 266.8 60.8Q265.8 62.4 265.8 62.9L265.8 '
    '62.9Q265.1 63.4 264.6 64.1Q264.2 64.8 264.2 64.8L264.2 64.8Q264.2 65.4 263.2 67.7Q262.3 70.1 '
    '260.9 72.9Q259.5 75.8 258.1 77.9L258.1 77.9L256 81.1M275.1 47.7L275.1 47.7Q275.1 47.7 276.1 '
    '47.5Q277.2 47.3 278.6 47Q280.1 46.8 281.3 46.8L281.3 46.8Q285.5 45.8 287.4 45.4Q289.3 45.1 '
    '290 45.1Q290.8 45.1 291.4 45.4L291.4 45.4Q291.8 45.9 292.1 46Q292.5 46.1 292.5 46.1L292.5 '
    '46.1Q292.6 45.9 292.8 43.8Q293 41.7 293.3 38.6Q293.7 35.5 294 32.1Q294.4 28.8 294.6 '
    '25.9Q294.8 23.1 294.9 21.6L294.9 21.6Q295 19.7 295.1 18.1Q295.2 16.6 295.2 16.6L295.2 '
    '16.6Q294.6 16.6 292.6 18.8Q290.7 21 288.3 24.6Q285.9 28.2 283.8 32.3L283.8 32.3Q282.8 34.2 '
    '281.9 35.7Q281 37.2 280.5 37.2L280.5 37.2Q280.3 37.4 279.3 38.9Q278.4 40.5 277.3 42.4Q276.2 '
    '44.4 275.5 45.9Q274.8 47.5 275.1 47.7';

/// Turns SVG path data into a [ui.Path]. path_parsing drives this through the same four
/// callbacks a browser's own path parser uses.
class _PathBuilder extends PathProxy {
  final ui.Path path = ui.Path();

  @override
  void close() => path.close();

  @override
  void cubicTo(double x1, double y1, double x2, double y2, double x3, double y3) =>
      path.cubicTo(x1, y1, x2, y2, x3, y3);

  @override
  void lineTo(double x, double y) => path.lineTo(x, y);

  @override
  void moveTo(double x, double y) => path.moveTo(x, y);
}

// Parsed and measured ONCE for the life of the isolate. Both are cheap enough to do, and both
// land on the one frame in the product where nothing may be spent — the frame that opens the
// app. computeMetrics() also returns a single-use iterable, so re-walking it every frame would
// mean re-measuring a 90-segment outline sixty times a second.
ui.Path? _cachedPath;
List<ui.PathMetric>? _cachedMetrics;
double _cachedTotal = 0;

ui.Path get _wordmarkPath {
  final cached = _cachedPath;
  if (cached != null) return cached;
  final builder = _PathBuilder();
  writeSvgPathDataToPath(kNivoraWordmarkPath, builder);
  return _cachedPath = builder.path;
}

List<ui.PathMetric> get _wordmarkMetrics {
  final cached = _cachedMetrics;
  if (cached != null) return cached;
  final metrics = _wordmarkPath.computeMetrics().toList(growable: false);
  _cachedTotal = metrics.fold<double>(0, (sum, m) => sum + m.length);
  return _cachedMetrics = metrics;
}

/// The wordmark, drawn to [progress] of its total outline length.
///
/// At 0 nothing is on screen; at 1 the whole signature is. Every value between is a legitimate
/// still of the same picture, which is exactly what lets the splash be cut off at any moment
/// without looking broken — see the note in features/splash/splash_screen.dart.
class NivoraWordmark extends StatelessWidget {
  const NivoraWordmark({
    super.key,
    required this.progress,
    required this.color,
    this.strokeWidth = 1.5,
  });

  final double progress;
  final Color color;

  /// In the path's own coordinate space — matching the web version's `stroke-width` — so the
  /// line keeps its weight relative to the letters at whatever size the mark is drawn.
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    // THE MARK IS THE WORD, so it has to say the word. Replacing a Text('NIVORA') with drawn
    // geometry silently removed the app's name from the accessibility tree — a blind user
    // opening the app would have been handed an unlabelled box. `image` marks it as a single
    // graphic rather than something to be explored by touch.
    return Semantics(
      label: 'NIVORA',
      image: true,
      child: CustomPaint(
        painter: _WordmarkPainter(progress: progress, color: color, strokeWidth: strokeWidth),
      ),
    );
  }
}

class _WordmarkPainter extends CustomPainter {
  const _WordmarkPainter({
    required this.progress,
    required this.color,
    required this.strokeWidth,
  });

  final double progress;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || size.isEmpty) return;

    final metrics = _wordmarkMetrics;
    if (metrics.isEmpty || _cachedTotal <= 0) return;

    final bounds = _wordmarkPath.getBounds();
    if (bounds.isEmpty) return;

    // Fit inside the box without distorting the letterforms, and centre the slack.
    final scale = math.min(size.width / bounds.width, size.height / bounds.height);
    canvas.save();
    canvas.translate(
      (size.width - bounds.width * scale) / 2 - bounds.left * scale,
      (size.height - bounds.height * scale) / 2 - bounds.top * scale,
    );
    canvas.scale(scale);

    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    // ONE BUDGET, SPENT IN ORDER. This is what makes it read as writing rather than as every
    // letter fading up at once: each sub-path takes what it needs from the remaining length,
    // and the next one begins only when the previous is finished.
    var remaining = _cachedTotal * progress.clamp(0.0, 1.0);
    for (final metric in metrics) {
      if (remaining <= 0) break;
      final take = math.min(remaining, metric.length);
      canvas.drawPath(metric.extractPath(0, take), pen);
      remaining -= take;
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_WordmarkPainter old) =>
      old.progress != progress || old.color != color || old.strokeWidth != strokeWidth;
}
