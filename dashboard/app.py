import streamlit as st
import pandas as pd
import pathlib

st.set_page_config(layout='wide', page_title='Engineer Impact — Prototype')

metrics_path = pathlib.Path(__file__).resolve().parents[1] / 'metrics.csv'
if not metrics_path.exists():
    st.error('metrics.csv not found. Run scripts/parse_git.py and scripts/aggregate_metrics.py first.')
    st.stop()

df = pd.read_csv(metrics_path)
top5 = df.sort_values('impact_score', ascending=False).head(5)

st.title('Top 5 Most Impactful Engineers')
cols = st.columns(5)
for i, (_, row) in enumerate(top5.iterrows()):
    cols[i].metric(label=row['creator'], value=f"{row['impact_score']:.1f}", delta=f"{int(row['total_future_mods_90d'])} future mods")

st.subheader('Why these engineers?')
for _, r in top5.iterrows():
    st.markdown(f"**{r['creator']}** — created {int(r['introduced_functions'])} functions that were modified {int(r['total_future_mods_90d'])} times within 90 days; median survivability {int(r['median_survivability'])} days.")
