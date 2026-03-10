import os
import re
import csv
import glob
from datetime import datetime

class TradeAnalyzerV2:
    def __init__(self, test_dir="test"):
        self.test_dir = test_dir
        self.inputs = {}
        self.deals = []
        self.log_index = {}
        self.report_file = ""
        self.log_file = ""
        
        # State Tracking
        self.sequences = {} # {magic: {state, midPrice, volBuy, volSell, open_positions}}
        self.profit_tally = 0.0
        self.active_magic = None
        
    def find_latest_files(self):
        reports = glob.glob(os.path.join(self.test_dir, "ReportTester-*.html"))
        if not reports:
            print(f"No HTML report found in {self.test_dir} folder.")
            return False
        self.report_file = max(reports, key=os.path.getmtime)
        
        logs = glob.glob(os.path.join(self.test_dir, "*.log"))
        if not logs:
            print(f"No log file found in {self.test_dir} folder.")
            return False
        self.log_file = max(logs, key=os.path.getmtime)
        
        print(f"Found Report: {self.report_file}")
        print(f"Found Log: {self.log_file}")
        return True

    def parse_html(self):
        if not self.report_file:
            return False
        
        content = ""
        for encoding in ['utf-16', 'utf-8', 'cp1252']:
            try:
                with open(self.report_file, 'r', encoding=encoding) as f:
                    content = f.read()
                if "Strategy Tester Report" in content:
                    print(f"Read HTML with {encoding}")
                    break
            except Exception:
                continue
        
        if not content:
            print("Failed to read HTML report.")
            return False

        input_pattern = re.compile(r'<b>\s*([^=<]+)=([^<]+)</b>')
        matches = input_pattern.findall(content)
        for key, val in matches:
            if key.strip() != "<unnamed>":
                self.inputs[key.strip()] = val.strip()
        
        print(f"Parsed {len(self.inputs)} parameters.")

        header_pos = content.find(">Deals<")
        if header_pos == -1:
            header_pos = content.find("Deals</b>")
            
        if header_pos != -1:
            table_end = content.find("</table>", header_pos)
            deals_html = content[header_pos:table_end]
            
            rows = re.findall(r'<tr.*?>.*?</tr>', deals_html, re.DOTALL)
            for row in rows:
                cols = re.findall(r'<td.*?>(.*?)</td>', row, re.DOTALL)
                if len(cols) >= 12:
                    deal_data = [re.sub(r'<[^>]+>', '', col).strip() for col in cols]
                    if not deal_data: continue
                    
                    if deal_data[1].isdigit():
                        comment = deal_data[12] if len(deal_data) > 12 else ""
                        deal = {
                            'Time': deal_data[0],
                            'Deal': deal_data[1],
                            'Symbol': deal_data[2],
                            'Type': deal_data[3],
                            'Direction': deal_data[4],
                            'Volume': deal_data[5],
                            'Price': deal_data[6],
                            'Order': deal_data[7],
                            'Commission': deal_data[8],
                            'Swap': deal_data[9],
                            'Profit': deal_data[10],
                            'Balance': deal_data[11],
                            'Comment': comment
                        }
                        self.deals.append(deal)
        
        print(f"Parsed {len(self.deals)} deals.")
        return True

    def parse_logs(self):
        if not self.log_file:
            return False
        
        lines = []
        for encoding in ['utf-16', 'utf-8', 'cp1252']:
            try:
                with open(self.log_file, 'r', encoding=encoding) as f:
                    lines = f.readlines()
                if lines:
                    print(f"Read Log with {encoding}")
                    break
            except Exception:
                continue
        
        self.log_index = {}
        time_pattern = re.compile(r'(\d{4}\.\d{2}\.\d{2} \d{2}:\d{2}:\d{2})')
        
        for line in lines:
            match = time_pattern.search(line)
            if match:
                log_time = match.group(1)
                if log_time not in self.log_index:
                    self.log_index[log_time] = []
                self.log_index[log_time].append(line.strip())
        
        print(f"Indexed {len(self.log_index)} unique timestamps in logs.")
        return True

    def clean_log(self, log_line):
        return re.sub(r'^[A-Z]+\s+\d+\s+\d{2}:\d{2}:\d{2}\.\d+\s+[A-Za-z0-9]+\s+\d+\s+\d{4}\.\d{2}\.\d{2}\s+\d{2}:\d{2}:\d{2}\s+', '', log_line)

    def get_magic_from_comment(self, comment):
        match = re.search(r'\[(\d+)\]', comment)
        if match:
            return int(match.group(1))
        return None

    def analyze(self):
        lot_size = float(self.inputs.get('LotSize', 0))
        contract_size = 100000.0
        output_data = []

        for deal in self.deals:
            time_str = deal['Time']
            comment = deal['Comment']
            deal_price = float(deal['Price'].replace(' ', '')) if deal['Price'] else 0.0
            type_str = deal['Type'].lower()
            direction = deal['Direction'].lower()
            volume = float(deal['Volume'].replace(' ', '')) if deal['Volume'] else 0.0
            order_id = deal['Order']
            deal_profit = float(deal['Profit'].replace(' ', '')) if deal['Profit'] else 0.0
            deal_comm = float(deal['Commission'].replace(' ', '')) if deal['Commission'] else 0.0
            deal_swap = float(deal['Swap'].replace(' ', '')) if deal['Swap'] else 0.0
            net_deal_profit = deal_profit + deal_comm + deal_swap
            
            magic = self.get_magic_from_comment(comment)
            related_logs = [self.clean_log(l) for l in self.log_index.get(time_str, [])]
            
            status = "PASS"
            reasoning = "N/A"
            calc_details = ""
            
            # --- State Update Logic ---
            if magic is not None:
                if magic not in self.sequences:
                    self.sequences[magic] = {
                        'state': 'ACTIVE',
                        'midPrice': 0.0,
                        'volBuy': 0.0,
                        'volSell': 0.0,
                        'open_positions': []
                    }
                
                seq = self.sequences[magic]
                
                if direction == 'in':
                    if type_str == 'buy':
                        seq['volBuy'] += volume
                    else:
                        seq['volSell'] += volume
                    seq['open_positions'].append({'vol': volume, 'price': deal_price, 'type': type_str, 'order': order_id})
                    
                    if "[HEDGE]" in comment:
                        seq['state'] = 'LOCKED'
                        # Calculate MidPrice when locked
                        buy_price = sum(p['price'] * p['vol'] for p in seq['open_positions'] if p['type'] == 'buy') / seq['volBuy']
                        sell_price = sum(p['price'] * p['vol'] for p in seq['open_positions'] if p['type'] == 'sell') / seq['volSell']
                        seq['midPrice'] = (buy_price + sell_price) / 2.0
                        reasoning = f"Sequence {magic} LOCKED"
                        calc_details = f"MidPrice: {round(seq['midPrice'], 5)}"
                    else:
                        # Signal Entry
                        if self.active_magic and self.active_magic != magic:
                            # Check if previous active magic is actually gone or still active
                            if self.sequences[self.active_magic]['state'] == 'ACTIVE':
                                status = "FAIL"
                                reasoning = "One-Active-Trade Rule Violation"
                                calc_details = f"New Magic {magic} entered while {self.active_magic} is still ACTIVE"
                        self.active_magic = magic
                        reasoning = f"Signal Entry (Magic {magic})"
                
                elif direction == 'out':
                    # Direction 'out' closes positions
                    remaining = volume
                    # First try to close the specific ticket if logged (though MT5 deals usually represent the closure)
                    # MT5 Deal direction 'out' means closing. Type Buy out = closing Sell. Type Sell out = closing Buy.
                    target_type = 'buy' if type_str == 'sell' else 'sell'
                    
                    i = 0
                    while i < len(seq['open_positions']) and remaining > 0:
                        if seq['open_positions'][i]['type'] == target_type:
                            drop = min(remaining, seq['open_positions'][i]['vol'])
                            seq['open_positions'][i]['vol'] -= drop
                            remaining -= drop
                            if target_type == 'buy': seq['volBuy'] -= drop
                            else: seq['volSell'] -= drop
                            
                            if seq['open_positions'][i]['vol'] <= 0.0001:
                                seq['open_positions'].pop(i)
                            else:
                                i += 1
                        else:
                            i += 1
                    
                    if net_deal_profit > 0:
                        self.profit_tally += net_deal_profit
                    
                    if "[TRIM]" in comment:
                        reasoning = "Symmetrical Trim"
                        # Validation: Check if it was indeed the farthest MidPrice
                        current_mprice = deal_price # Approximated
                        # Note: True farthest check requires knowing prices of ALL segments at this time.
                        # We can check among our tracked sequences.
                        max_dist = -1
                        farthest_m = None
                        for m, data in self.sequences.items():
                            if data['state'] == 'LOCKED' and (data['volBuy'] > 0 or data['volSell'] > 0):
                                dist = abs(data['midPrice'] - current_mprice)
                                if dist > max_dist:
                                    max_dist = dist
                                    farthest_m = m
                        
                        if farthest_m and farthest_m != magic:
                            # It's possible multiple are close, but if significantly different, flag it.
                            # For now, just log the comparison.
                            calc_details = f"Trimmed M:{magic} (Dist: {round(abs(seq['midPrice']-current_mprice), 5)}). Farthest seen: M:{farthest_m} (Dist: {round(max_dist, 5)})"
                        
                        # Validate symmetry: MT5 deals for trims come in pairs usually.
                        # We'll see if volBuy and volSell remain balanced.
                        if abs(seq['volBuy'] - seq['volSell']) > 0.001:
                            status = "WARNING"
                            reasoning += " | Asymmetry Detected"
                    
                    elif "sl" in comment or "Trailing" in comment:
                        reasoning = "Active Trade Exit (SL)"
                        if seq['volBuy'] <= 0.0001 and seq['volSell'] <= 0.0001:
                            seq['state'] = 'CLOSED'
                            if self.active_magic == magic:
                                self.active_magic = None
            
            # --- General Rule Checks ---
            if "[SIGNAL]" in comment and direction == 'in':
                if abs(volume - lot_size) > 0.001:
                    status = "FAIL"
                    reasoning = "Lot Size Mismatch"
                    calc_details = f"Expected {lot_size}, got {volume}"

            # --- Result Construction ---
            analysis = {
                **deal,
                'Magic': magic,
                'Seq_State': self.sequences[magic]['state'] if magic in self.sequences else "N/A",
                'Seq_MidPrice': round(self.sequences[magic]['midPrice'], 5) if magic in self.sequences else 0,
                'Profit_Tally': round(self.profit_tally, 2),
                'Test_Status': status,
                'Reasoning': reasoning,
                'Details': calc_details
            }
            output_data.append(analysis)

        return output_data

    def save_csv(self, data, filename="test/v2_trade_analysis.csv"):
        if not data:
            return
        keys = data[0].keys()
        os.makedirs(os.path.dirname(filename), exist_ok=True)
        with open(filename, 'w', newline='', encoding='utf-8') as f:
            dict_writer = csv.DictWriter(f, fieldnames=keys)
            dict_writer.writeheader()
            dict_writer.writerows(data)
        print(f"Saved analysis to {filename}")
        
        try:
            print(f"Opening {filename}...")
            os.startfile(os.path.abspath(filename))
        except Exception as e:
            print(f"Could not open file: {e}")

if __name__ == "__main__":
    analyzer = TradeAnalyzerV2()
    if analyzer.find_latest_files():
        if analyzer.parse_html() and analyzer.parse_logs():
            results = analyzer.analyze()
            analyzer.save_csv(results)
