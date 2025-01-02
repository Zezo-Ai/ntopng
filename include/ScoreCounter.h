/*
 *
 * (C) 2020-25 - ntop.org
 *
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
 *
 */

#ifndef _SCORE_COUNTER_H_
#define _SCORE_COUNTER_H_

class ScoreCounter {
 private:
  u_int32_t value, decay_time, beta /* Old value before decrease */;
  float alpha; /* Linear decrease rate */

 public:
  ScoreCounter()  { value = decay_time = 0, alpha = 0, beta = 0; }

  u_int32_t get();
  
  inline u_int32_t inc(u_int16_t score) { value += score, decay_time = 0; return(value); }

  u_int32_t dec(u_int16_t score);
};

#endif /* _SCORE_COUNTER_H_ */
